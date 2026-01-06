Get-ADObject -Filter * -SearchBase "DC=GREAT,DC=CRETACEOUS" | Group-Object ObjectClass | Select-Object Name, Count
