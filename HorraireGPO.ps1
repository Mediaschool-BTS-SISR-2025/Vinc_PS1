Import-Module ActiveDirectory

# Liste des écoles
$ecoles = @("simone-veil", "robert-batinder", "jules-ferry", "robert-dedre", "louis-pasteur", "emile-zola", "louise-michel")

# Liste des niveaux scolaire
$niveaux = @("cp", "ce1", "ce2", "cm1", "cm2")

# Catégories d'utilisateurs à créer dans chaque école
$categories = @("enseignant", "direction")

## autoriser la connexion de 9h à 17h du lundi au vendredi
[byte[]]$hours_eleve = @(0, 0, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 0) 
## autoriser la connexion de 7h à 20h du lundi au vendredi           
[byte[]]$hours_enseignant = @(0, 0, 0, 192, 255, 7, 192, 255, 7, 192, 255, 7, 192, 255, 7, 192, 255, 7, 0, 0, 0)

	
foreach ($ecole in $ecoles) {
    foreach ($niveau in $niveaux) {
        # Nom du groupe basé sur l'école et du niveau
        $nomGroupe = "${niveau}-${ecole}"
        $group = Get-ADGroup -Filter "Name -eq '$nomGroupe'" -ErrorAction SilentlyContinue
        if ($group) {
            $members = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.objectClass -eq 'user' }
            foreach ($member in $members) {
                Set-ADUser -Identity $member.distinguishedName -Replace @{logonhours = $hours_eleve }
                Write-Host "Heures de connexion mises à jour pour $($member.SamAccountName)."
            }
        }
        else {
            Write-Host "Le groupe $nomGroupe n'existe pas."
        }
    }
}


foreach ($ecole in $ecoles) {
    foreach ($categorie in $categories) {
        # Nom du groupe basé sur l'école et la catégorie
        $nomGroupe = "${categorie}-${ecole}"
        $group = Get-ADGroup -Filter "Name -eq '$nomGroupe'" -ErrorAction SilentlyContinue
        if ($group) {
            $members = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.objectClass -eq 'user' }
            foreach ($member in $members) {
                Set-ADUser -Identity $member.distinguishedName -Replace @{logonhours = $hours_enseignant }
                Write-Host "Heures de connexion mises à jour pour $($member.SamAccountName)."
            }
        }
        else {
            Write-Host "Le groupe $nomGroupe n'existe pas."
        }
    }
}
