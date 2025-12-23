$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"

Write-Host "Starting Restore..." -ForegroundColor Cyan

Copy-Item "$BackupPath\*.dns.bak" "C:\Windows\System32\dns"

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

        Write-Host "  Converting to AD: $Zone" -NoNewline
        dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Warning "  Failed to restore $Zone"
    }
}

Restart-Service DNS
Restart-Service Netlogon
Write-Host "Restore Complete. Testing AD..." -ForegroundColor Yellow
nltest /dsgetdc:
