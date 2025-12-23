$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"
$MaxTries = 30
$TryCount = 0
$Success = $false

Write-Host "--- PHASE 0: ROLE & BINARY VERIFICATION ---" -ForegroundColor Cyan
$RequiredFeatures = @("DNS", "AD-Domain-Services")
foreach ($Feat in $RequiredFeatures) {
    if ((Get-WindowsFeature $Feat).InstallState -ne "Installed") {
        Write-Warning "$Feat Role missing! Reinstalling..."
        Install-WindowsFeature $Feat -IncludeManagementTools
    }
}

Write-Host "--- PHASE 1: HEALING SYSTEM LOGIC ---" -ForegroundColor Cyan
if (Test-Path "$BackupPath\DNS_Settings.reg") {
    Write-Host "  Importing Registry Settings..."
    reg import "$BackupPath\DNS_Settings.reg"
}

Write-Host "  Syncing Time Service..."
Set-Service W32Time -StartupType Automatic
Start-Service W32Time -ErrorAction SilentlyContinue
w32tm /resync /force | Out-Null


klist purge -li 0x3e7 

Write-Host "--- PHASE 2: DATA RESTORATION ---" -ForegroundColor Cyan
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

Write-Host "--- PHASE 3: SERVICE STABILIZATION ---" -ForegroundColor Cyan
Start-Service DNS, Netlogon

while ((Get-Service Netlogon).Status -ne 'Running') { 
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 1 
}

ipconfig /registerdns
nltest /dsregdns 

Write-Host "--- PHASE 4: AD CONVERSION (SMART RETRY) ---" -ForegroundColor Cyan


while ($TryCount -lt $MaxTries -and -not $Success) {
    $TryCount++
    Write-Host "Attempting to Migrate to AD storage..." -ForegroundColor Yellow
    
    foreach ($Row in $ZoneList) {
        $Zone = $Row.ZoneName
        if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }
        dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
    }

    $CheckZone = ($ZoneList | Where-Object { $_.ZoneName -ne "TrustAnchors" })[0].ZoneName
    $Status = Get-DnsServerZone -Name $CheckZone -ErrorAction SilentlyContinue
    
    if ($Status.IsDsIntegrated -eq $true) {
        $Success = $true
        Write-Host " [SUCCESS] Zones confirmed in Active Directory." -ForegroundColor Green
    } else {
        if ($TryCount -eq 15) { 
            Write-Host " [ACTION] Halfway point. Re-purging tickets and kicking Netlogon..." -ForegroundColor Cyan
            klist purge -li 0x3e7
            Restart-Service Netlogon -Force 
            nltest /dsregdns
        }
        Write-Host " [WAITING] AD partition not ready. Retrying in 10 seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
}

if (-not $Success) { 
    Write-Error "CRITICAL: DNS failed to integrate. Please check Event ID 5774 in Netlogon logs."
}

Write-Host "Restore Process Finished." -ForegroundColor Yellow
nltest /dsgetdc:
