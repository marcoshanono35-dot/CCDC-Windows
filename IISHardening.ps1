$SiteName   = "WordPress"
$WebRoot    = "C:\inetpub\wwwroot\wordpress"
$UploadsDir = "$WebRoot\wp-content\uploads"
$AppPool    = "WordPressAppPool"


Set-WebConfigurationProperty `
 -Filter system.webServer/directoryBrowse `
 -Name enabled `
 -Value false `
 -PSPath IIS:\Sites\$SiteName

$blocked = @(".exe",".bat",".cmd",".ps1",".vbs",".phtml",".php5")

foreach ($ext in $blocked) {
  Add-WebConfiguration `
    -PSPath IIS:\Sites\$SiteName `
    -Filter system.webServer/security/requestFiltering/fileExtensions `
    -Value @{ fileExtension=$ext; allowed="false" }
}

@"
<configuration>
 <system.webServer>
  <handlers>
   <clear />
  </handlers>
 </system.webServer>
</configuration>
"@ | Out-File "$UploadsDir\web.config" -Encoding UTF8 -Force

icacls $WebRoot /inheritance:r
icacls $WebRoot /grant "IIS AppPool\${AppPool}:(OI)(CI)RX"
icacls $UploadsDir /grant "IIS AppPool\${AppPool}:(OI)(CI)M"

icacls "$WebRoot\wp-config.php" /inheritance:r
icacls "$WebRoot\wp-config.php" /grant "IIS AppPool\$AppPool:R"

$headers = @{
 "X-Frame-Options"="DENY"
 "X-Content-Type-Options"="nosniff"
 "Referrer-Policy"="strict-origin"
 "Strict-Transport-Security"="max-age=31536000"
}

foreach ($h in $headers.Keys) {
 Add-WebConfigurationProperty `
  -PSPath IIS:\Sites\$SiteName `
  -Filter system.webServer/httpProtocol/customHeaders `
  -Name "." `
  -Value @{name=$h;value=$headers[$h]}
}

Set-NetFirewallProfile `
 -Profile Domain,Private,Public `
 -DefaultInboundAction Block `
 -DefaultOutboundAction Allow `
 -LogBlocked True

New-NetFirewallRule -DisplayName "Allow HTTP"  -Direction Inbound -Protocol TCP -LocalPort 80  -Action Allow
New-NetFirewallRule -DisplayName "Allow HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow

$base = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"

foreach ($p in "SSL 3.0","TLS 1.0","TLS 1.1") {
 New-Item "$base\$p\Server" -Force | Out-Null
 Set-ItemProperty "$base\$p\Server" Enabled 0
}

Set-WebConfigurationProperty `
 -Filter system.applicationHost/sites/siteDefaults/logFile `
 -Name logFormat `
 -Value W3C
