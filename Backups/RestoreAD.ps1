$BackupPath = "C:\AD_Backup"
$IFMPath = "$BackupPath\AD_Database"
$UserCSV = "$BackupPath\UserSnapshot.csv"
$GPOPath = "$BackupPath\GPOs"

Write-Host "--- Active Directory Restoration Tool ---" -ForegroundColor Cyan

if (-not (Test-Path $BackupPath)) {
    Write-Host "[!] ERROR: Backup not found at $BackupPath" -ForegroundColor Red
    return
}

$SafeMode = Test-Path "HKLM:\System\CurrentControlSet\Control\SafeBoot\Option"

if ($SafeMode) {
    Write-Host "[!] DSRM DETECTED: Proceeding with Actual Database Restore." -ForegroundColor Yellow
    
    $LiveNtds = "C:\Windows\NTDS\ntds.dit"
    if (Test-Path "$IFMPath\Active Directory\ntds.dit") {
        Write-Host "Seeding database file from backup..." -ForegroundColor Cyan
        Copy-Item -Path "$IFMPath\Active Directory\ntds.dit" -Destination $LiveNtds -Force
    }

    Write-Host "Restoring database... Watch for the manual popup dialog!" -ForegroundColor Yellow
    @("activate instance ntds", "authoritative restore", "restore database", "quit", "quit") | ntdsutil

    
} 
else {
    Write-Host "[*] NORMAL MODE DETECTED: Proceeding with Surgical Fixes." -ForegroundColor Yellow

    if (Test-Path $UserCSV) {
        Write-Host "Reconstructing Users/Groups from CSV Map..." -ForegroundColor Cyan
        $Users = Import-Csv $UserCSV
        foreach ($U in $Users) {
            $SAM = $U.SamAccountName
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$SAM'" -ErrorAction SilentlyContinue)) {
                $OU = $U.DistinguishedName.Substring($U.DistinguishedName.IndexOf("OU="))
                $Pass = ConvertTo-SecureString "P@ssword123!" -AsPlainText -Force
                New-ADUser -Name $SAM -SamAccountName $SAM -Path $OU -AccountPassword $Pass -Enabled $true
            }
            if ($U.MemberOf) {
                $Groups = $U.MemberOf -split ';' | ForEach-Object { if ($_ -match "CN=([^,]+)") { $matches[1] } }
                foreach ($G in $Groups) { Add-ADGroupMember -Identity $G -Members $SAM -ErrorAction SilentlyContinue }
            }
        }
    }

    if (Test-Path $GPOPath) {
        Write-Host "Importing GPO Exports..." -ForegroundColor Cyan
        Get-ChildItem $GPOPath -Directory | ForEach-Object {
            Import-GPO -BackupId $_.Name -Path $GPOPath -CreateIfNeeded | Out-Null
        }
    }
    
    Write-Host "--- Reconstruction Complete. Run 'gpupdate /force' ---" -ForegroundColor Green
}
