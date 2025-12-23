$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"
$trycount = 0
$success = $false

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

Write-Host "--- PHASE 3: AD CONVERSION (RETRY LOOP) ---" -ForegroundColor Cyan

while ($trycount -lt 5 -and $success -eq $false) {
    $trycount++
    Write-Host "Attempt $trycount: Converting zones to AD-Integrated..." -ForegroundColor Yellow
    
    foreach ($Row in $ZoneList) {
        $Zone = $Row.ZoneName
        if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }
        dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
    }

    $CheckZone = ($ZoneList | Where-Object { $_.ZoneName -ne "TrustAnchors" })[0].ZoneName
    $Status = Get-DnsServerZone -Name $CheckZone -ErrorAction SilentlyContinue
    
    if ($Status.IsDsIntegrated -eq $true) {
        $success = $true
        Write-Host " [SUCCESS] Zones confirmed in Active Directory." -ForegroundColor Green
    } else {
        Write-Host " [WAITING] AD partition not ready. Retrying in 5 seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $success) {
    Write-Error "CRITICAL: Zones failed to integrate after 5 attempts."
}

Write-Host "Restore Complete. Testing DC Locator..." -ForegroundColor Yellow
nltest /dsgetdc:
