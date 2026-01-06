# --- CONFIGURATION ---
$BackupPath = "C:\AD_Backup"
$IFMPath = "$BackupPath\AD_Database"
$UserCSV = "$BackupPath\UserSnapshot.csv"
$GPOPath = "$BackupPath\GPOs"

# 1. CHECK FOR DSRM (SAFE MODE)
# Reliability: WMI BootupState often returns null; the registry is the source of truth.
$SafeMode = Test-Path "HKLM:\System\CurrentControlSet\Control\SafeBoot\Option"

Write-Host "`n--- MANUAL RESTORATION GUIDE ---" -ForegroundColor Cyan
Write-Host "Because auto-entry is failing, follow these steps exactly." -ForegroundColor White

if ($SafeMode) {
    Write-Host "[!] DSRM DETECTED: Use these commands to restore the database." -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------"
    
    Write-Host "STEP 1: Seed the database file (Initializes Jet Engine)" -ForegroundColor Cyan
    Write-Host "Copy-Item -Path `"$IFMPath\Active Directory\ntds.dit`" -Destination `"C:\Windows\NTDS\ntds.dit`" -Force"
    Write-Host ""

    Write-Host "STEP 2: Run ntdsutil and enter these sub-commands" -ForegroundColor Cyan
    Write-Host "Type 'ntdsutil' then enter each of these:"
    Write-Host "  activate instance ntds"
    Write-Host "  authoritative restore"
    Write-Host "  restore database"
    Write-Host "  (Click 'YES' on the popup dialog box on the desktop)"
    Write-Host "  quit"
    Write-Host "  quit"
    Write-Host ""

    Write-Host "STEP 3: Return to Normal Mode" -ForegroundColor Cyan
    Write-Host "bcdedit /deletevalue {current} safeboot"
    Write-Host "Restart-Computer"
} 
else {
    Write-Host "[*] NORMAL MODE DETECTED: Proceeding with Surgical Fixes." -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------"

    Write-Host "STEP 1: Fix System Time (Resolves GitHub/SSL Cert Errors)" -ForegroundColor Cyan
    Write-Host "Set-Date -Date `"01/06/2026 15:30`"  <-- (Update this to current time)"
    Write-Host ""

    Write-Host "STEP 2: Import GPOs (Do not use -All parameter)" -ForegroundColor Cyan
    Write-Host "Get-ChildItem `"$GPOPath`" -Directory | ForEach-Object { Import-GPO -BackupId `$_.Name -Path `"$GPOPath`" -CreateIfNeeded }"
    Write-Host ""

    Write-Host "STEP 3: Reconstruct Users from CSV (ADWS must be running)" -ForegroundColor Cyan
    Write-Host "`$Users = Import-Csv `"$UserCSV`""
    Write-Host "foreach (`$U in `$Users) { New-ADUser -Name `$U.SamAccountName -SamAccountName `$U.SamAccountName -Path (`$U.DistinguishedName.Substring(`$U.DistinguishedName.IndexOf('OU='))) -Enabled `$true }"
    Write-Host ""

    Write-Host "--- IF YOU NEED TO ENTER DSRM AGAIN ---" -ForegroundColor Red
    Write-Host "bcdedit /set {current} safeboot dsrepair"
    Write-Host "Restart-Computer"
}
