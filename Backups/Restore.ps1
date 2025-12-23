$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"

Write-Host "Starting Restore..." -ForegroundColor Cyan

Copy-Item "$BackupPath\*.dns.bak" "C:\Windows\System32\dns"

Stop-Service DNS, Netlogon -Force

foreach ($Row in $ZoneList) {
    $Zone = $Row.ZoneName
    if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }

    $BakFile = "C:\Windows\System32\dns\$Zone.dns.bak"
    $RealFile = "C:\Windows\System32\dns\$Zone.dns"
    
    if (Test-Path $BakFile) {
        Move-Item $BakFile $RealFile -Force
    }

    try {
        Write-Host "  Loading Zone: $Zone" -NoNewline
        dnscmd /ZoneAdd $Zone /Primary /file "$Zone.dns" /load | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Failed to load $Zone"
    }
}

Start-Service DNS
Start-Service Netlogon

Write-Host "Waiting for Active Directory to stabilize..." -ForegroundColor Yellow
while ((Get-Service Netlogon).Status -ne 'Running') { Start-Sleep -Seconds 2 }

Start-Sleep -Seconds 10 

foreach ($Row in $ZoneList) {
    $Zone = $Row.ZoneName
    if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }

    try {
        Write-Host "  Converting to AD: $Zone" -NoNewline
        # The /dsprimary command requires the AD DS partition to be reachable
        dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Failed to convert $Zone. AD partition might not be ready."
    }
}

Write-Host "Force-registering DC records..." -ForegroundColor Cyan
ipconfig /registerdns
nltest /dsregdns

Write-Host "Restore Complete. Testing AD..." -ForegroundColor Yellow
nltest /dsgetdc:
