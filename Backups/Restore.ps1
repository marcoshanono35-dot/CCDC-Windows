$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"
$MaxTries = 30
$TryCount = 0
$Success = $false

Write-Host "--- PHASE 0: BINARY CHECK ---" -ForegroundColor Cyan
$RequiredFeatures = @("DNS", "AD-Domain-Services")
foreach ($Feature in $RequiredFeatures) {
    if ((Get-WindowsFeature $Feature).InstallState -ne "Installed") {
        Write-Warning "$Feature Role not found! Reinstalling..."
        Install-WindowsFeature $Feature -IncludeManagementTools
    }
}

Write-Host "--- PHASE 1: HEALING CONFIGURATION ---" -ForegroundColor Cyan

if (Test-Path "$BackupPath\DNS_Settings.reg") {
    Write-Host "Importing Registry Settings..."
    reg import "$BackupPath\DNS_Settings.reg"
}

Stop-Service DNS, Netlogon -Force 

Copy-Item "$BackupPath\*.dns.bak" "C:\Windows\System32\dns"

foreach ($Row in $ZoneList) {
    $Zone = $Row.ZoneName
    if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }
    
    $BakFile = "C:\Windows\System32\dns\$Zone.dns.bak"
    $RealFile = "C:\Windows\System32\dns\$Zone.dns"
    
    if (Test-Path $BakFile) {
        Move-Item $BakFile $RealFile -Force
    }
    
    Write-Host "  Loading $Zone as file-backed..." -NoNewline
    dnscmd /ZoneAdd $Zone /Primary /file "$Zone.dns" /load | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
}

Write-Host "--- PHASE 2: SERVICE STABILIZATION ---" -ForegroundColor Cyan
Start-Service DNS, Netlogon

while ((Get-Service Netlogon).Status -ne 'Running') { 
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 1 
}

ipconfig /registerdns
nltest /dsregdns 

Write-Host "--- PHASE 3: AD CONVERSION (SMART RETRY) ---" -ForegroundColor Cyan

while ($TryCount -lt $MaxTries -and -not $Success) {
    $TryCount++
    Write-Host "Attempt $TryCount of $MaxTries: Migrating to AD storage..." -ForegroundColor Yellow
    
    foreach ($Row in $ZoneList) {
        $Zone = $Row.ZoneName
        if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }
        dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
    }

    $CheckZone = ($ZoneList | Where-Object { $_.ZoneName -ne "TrustAnchors" })[0].ZoneName
    $Status = Get-DnsServerZone -Name $CheckZone -ErrorAction SilentlyContinue

    if ($Status.IsDsIntegrated -eq $true) {
        Write-Host " [SUCCESS] Zones confirmed in Active Directory database." -ForegroundColor Green
    } 
    else {
        if ($TryCount -eq 15) { 
            Write-Host " [ACTION] Mid-point reached. Restarting Netlogon to force sync..." -ForegroundColor Cyan
            Restart-Service Netlogon -Force 
        }
        
        Write-Host " [WAITING] AD partition not ready. Retrying in 5 seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 10  
    }
   
}

if (-not $Success) { 
    Write-Error "CRITICAL: DNS failed to integrate after $MaxTries attempts." 
}

Write-Host "Restore Process Finished." -ForegroundColor Yellow
nltest /dsgetdc:
