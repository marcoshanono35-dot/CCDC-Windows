$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"
$MaxTries = 30
$TryCount = 0
$Success = $false

Write-Host "--- PHASE 0: ROLE & NETWORK HEALING ---" -ForegroundColor Cyan
$RequiredFeatures = @("DNS", "AD-Domain-Services")
foreach ($Feat in $RequiredFeatures) {
    if ((Get-WindowsFeature $Feat).InstallState -ne "Installed") {
        Install-WindowsFeature $Feat -IncludeManagementTools
    }
}

Write-Host "  Resetting DNS Client to Loopback (Fixes 1014)..."
Get-NetIPInterface -AddressFamily IPv4 | Set-DnsClientServerAddress -ServerAddresses ("127.0.0.1")

Write-Host "--- PHASE 1: SECURITY & TIME HEALING ---" -ForegroundColor Cyan
Set-Service W32Time -StartupType Automatic
Start-Service W32Time -ErrorAction SilentlyContinue
w32tm /resync /force | Out-Null

Write-Host "  Purging Kerberos & Restarting KDC (Fixes 2170/2209)..."
klist purge -li 0x3e7
Restart-Service KDC -Force

if (Test-Path "$BackupPath\DNS_Settings.reg") {
    reg import "$BackupPath\DNS_Settings.reg"
}

Write-Host "--- PHASE 2: DATA & SERVICE RESET ---" -ForegroundColor Cyan
Stop-Service DNS, Netlogon -Force 

Copy-Item "$BackupPath\*.dns.bak" "C:\Windows\System32\dns"
foreach ($Row in $ZoneList) {
    $Zone = $Row.ZoneName
    if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }
    $BakFile = "C:\Windows\System32\dns\$Zone.dns.bak"
    $RealFile = "C:\Windows\System32\dns\$Zone.dns"
    if (Test-Path $BakFile) { Move-Item $BakFile $RealFile -Force }
    dnscmd /ZoneAdd $Zone /Primary /file "$Zone.dns" /load | Out-Null
}

Write-Host "--- PHASE 3: BREAKING THE 5781 DEADLOCK ---" -ForegroundColor Cyan
Start-Service DNS, Netlogon
while ((Get-Service Netlogon).Status -ne 'Running') { Start-Sleep -Seconds 1 }

Write-Host "  Forcing SRV Registration..."
ipconfig /registerdns
nltest /dsregdns 
Restart-Service Netlogon -Force

Write-Host "--- PHASE 4: AD CONVERSION (FINAL RETRY LOOP) ---" -ForegroundColor Cyan


while ($TryCount -lt $MaxTries -and -not $Success) {
    $TryCount++
    Write-Host "Attemptin to Migrate to AD storage..." -ForegroundColor Yellow
    
    foreach ($Row in $ZoneList) {
        $Zone = $Row.ZoneName
        if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }
        dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
    }

    $CheckZone = ($ZoneList | Where-Object { $_.ZoneName -ne "TrustAnchors" })[0].ZoneName
    $Status = Get-DnsServerZone -Name $CheckZone -ErrorAction SilentlyContinue
    
    if ($Status.IsDsIntegrated -eq $true) {
        $Success = $true
        Write-Host " [SUCCESS] DNS and AD are now fully integrated." -ForegroundColor Green
    } else {
        if ($TryCount -eq 15) { 
            Write-Host " [ACTION] Mid-point: Re-kicking KDC and Netlogon..." -ForegroundColor Cyan
            Restart-Service KDC, Netlogon -Force 
            nltest /dsregdns
        }
        Start-Sleep -Seconds 10
    }
}

if (-not $Success) { 
    Write-Error "CRITICAL: AD Integration failed. Check Directory Service log for Event 1000 (Database Corruption)."
}

nltest /dsgetdc:
