Write-Warning "STARTING DESTRUCTIVE WIPE IN 5 SECONDS. CTRL+C TO CANCEL."
Start-Sleep -Seconds 5

# 1. Delete all DNS Zones (The Data Wipe)
Get-DnsServerZone | Where-Object {$_.ZoneName -ne "TrustAnchors"} | ForEach-Object {
    Write-Host "Deleting Zone: $($_.ZoneName)" -ForegroundColor Red
    Remove-DnsServerZone -Name $_.ZoneName -Force -ErrorAction SilentlyContinue
}

# 2. Corrupt/Delete Registry Settings (The Config Wipe)
# This simulates a Red Teamer deleting your forwarders, logging, and tuning
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters" -Name "Forwarders" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters" -Name "LogFileMaxSize" -Value 0 -ErrorAction SilentlyContinue

# 3. Flush the Cache and Restart Service to apply the damage
Clear-DnsServerCache -Force
Restart-Service DNS -Force

Write-Host "DNS SERVER WIPED. SYSTEM CRIPPLED." -ForegroundColor Red -BackgroundColor Black
