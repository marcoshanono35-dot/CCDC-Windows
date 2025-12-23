$BackupPath = "C:\DNS_Backup"
$ZoneList = Import-Csv "$BackupPath\ZoneList.csv"

Write-Host "--- PHASE 1: FILE RESTORE ---" -ForegroundColor Cyan
Stop-Service DNS, Netlogon -Force
Copy-Item "$BackupPath\*.dns.bak" "C:\Windows\System32\dns"

foreach ($Row in $ZoneList) {
    $Zone = $Row.ZoneName
    if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }

    if (Test-Path "C:\Windows\System32\dns\$Zone.dns.bak") {
        Move-Item "C:\Windows\System32\dns\$Zone.dns.bak" "C:\Windows\System32\dns\$Zone.dns" -Force
    }

    dnscmd /ZoneAdd $Zone /Primary /file "$Zone.dns" /load
}

Write-Host "--- PHASE 2: SERVICE STABILIZATION ---" -ForegroundColor Cyan
Start-Service DNS, Netlogon
Write-Host "Waiting 15 seconds for AD Partition to mount..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

ipconfig /registerdns
nltest /dsregdns 

Write-Host "--- PHASE 3: AD CONVERSION ---" -ForegroundColor Cyan
foreach ($Row in $ZoneList) {
    $Zone = $Row.ZoneName
    if ($Zone -eq "." -or $Zone -eq "TrustAnchors") { continue }

    Write-Host "Converting $Zone to AD-Integrated..." -NoNewline
    dnscmd /ZoneResetType $Zone /dsprimary | Out-Null
    
    if ($LASTEXITCODE -eq 0) { Write-Host " [SUCCESS]" -ForegroundColor Green }
    else { Write-Host " [RETRY NEEDED]" -ForegroundColor Red }
}
