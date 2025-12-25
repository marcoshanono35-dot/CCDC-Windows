# --- CONFIGURATION ---
$BackupPath = "C:\AD_Backup"
$IFMPath = "$BackupPath\AD_Database"
$UserCSV = "$BackupPath\UserSnapshot.csv"
$GPOPath = "$BackupPath\GPOs"

Write-Host "--- Active Directory Restoration Tool ---" -ForegroundColor Cyan

# Check if backup exists
if (-not (Test-Path $BackupPath)) {
    Write-Host "[!] ERROR: Backup not found at $BackupPath" -ForegroundColor Red
    return
}

# 1. CHECK FOR DSRM (SAFE MODE)
$SafeMode = Test-Path "HKLM:\System\CurrentControlSet\Control\SafeBoot\Option"
if ($SafeMode) {
    Write-Host "[!] DSRM DETECTED: Proceeding with Actual Database Restore." -ForegroundColor Yellow
    
    # PHASE 1: THE BRAIN (NTDS.DIT)
    ntdsutil "activate instance ntds" "authoritative restore" "restore database" quit quit

    Write-Host "Restoring from IFM Backup... Watch for the manual popup dialog!" -ForegroundColor Yellow
    ntdsutil /s $CommandFile
    Remove-Item $CommandFile
    Write-Host "--- Database Restored. REBOOT to Normal Mode now. ---" -ForegroundColor Green
} 
else {
    Write-Host "[*] NORMAL MODE DETECTED: Proceeding with Surgical Fixes." -ForegroundColor Yellow

    # PHASE 2: RECONSTRUCT FROM CSV
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
            # Re-link memberships
            if ($U.MemberOf) {
                $Groups = $U.MemberOf -split ';' | ForEach-Object { if ($_ -match "CN=([^,]+)") { $matches[1] } }
                foreach ($G in $Groups) { Add-ADGroupMember -Identity $G -Members $SAM -ErrorAction SilentlyContinue }
            }
        }
    }

    # PHASE 3: RESTORE GPOs
    if (Test-Path $GPOPath) {
        Write-Host "Importing GPO Exports..." -ForegroundColor Cyan
        Import-Gpo -All -Path $GPOPath -CreateIfNeeded | Out-Null
    }
    
    Write-Host "--- Reconstruction Complete. Run 'gpupdate /force' ---" -ForegroundColor Green
}
