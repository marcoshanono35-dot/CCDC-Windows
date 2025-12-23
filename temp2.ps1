Write-Warning "STARTING DESTRUCTIVE WIPE IN 5 SECONDS. CTRL+C TO CANCEL."
Start-Sleep -Seconds 5

# Define system-protected zones that cause the script to hang
$Protected = @("TrustAnchors", "0.in-addr.arpa", "127.in-addr.arpa", "255.in-addr.arpa")

# 1. Delete all DNS Zones (The Data Wipe) - Logic Updated
Get-DnsServerZone | Where-Object { $_.ZoneName -notin $Protected } | ForEach-Object {
    Write-Host "Deleting Zone: $($_.ZoneName)" -ForegroundColor Red
    Remove-DnsServerZone -Name $_.ZoneName -Force -ErrorAction SilentlyContinue
}

# 2. Corrupt/Delete Registry Settings (The Config Wipe)
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters" -Name "Forwarders" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DNS\Parameters" -Name "LogFileMaxSize" -Value 0 -ErrorAction SilentlyContinue

# 3. Flush the Cache and Restart Service
Clear-DnsServerCache -Force
Restart-Service DNS -Force

Write-Host "DNS SERVER WIPED. Protected system zones were bypassed." -ForegroundColor Red -BackgroundColor Black
