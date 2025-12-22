Get-DnsServerZone | ForEach-Object {
    $name = $_.ZoneName
    Get-DnsServerResourceRecord -ZoneName $name | 
    Select-Object @{n='Zone';e={$name}}, HostName, RecordType, @{n='Data';e={$_.RecordData.IPv4Address.IPAddressToString}} | 
    Export-Csv -Append -Path "C:\DNS_Snapshot.csv" -NoTypeInformation
}

reg export "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DNS\Parameters" C:\DNS_Settings.reg
