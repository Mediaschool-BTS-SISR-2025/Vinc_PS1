# HorraireGPO.ps1
# Script pour configurer les restrictions horaires et les OUs dans Active Directory
# Date: 2025-06-13
# Auteur: Vinceadr

# Vérifier si les modules nécessaires sont disponibles
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "Module ActiveDirectory non installé. Installation en cours..." -ForegroundColor Yellow
    try {
        Import-Module ServerManager
        Add-WindowsFeature RSAT-AD-PowerShell
        Write-Host "Module ActiveDirectory installé avec succès." -ForegroundColor Green
    }
    catch {
        Write-Host "ERREUR: Impossible d'installer le module ActiveDirectory. Veuillez l'installer manuellement." -ForegroundColor Red
        return
    }
}

# Importation des modules
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
if (-not (Get-Module ActiveDirectory)) {
    Write-Host "ERREUR: Impossible de charger le module ActiveDirectory. Veuillez vérifier votre installation." -ForegroundColor Red
    return
}

function Set-HorraireGPO {
    param (
        [string]$LogPath = "$PSScriptRoot\HorraireGPO_log.txt",
        [string]$OutputCSVPath = "$PSScriptRoot\users.csv"  # MODIFIÉ pour utiliser users.csv au lieu de utilisateurs_fictifs.csv
    )

    # Récupération de la date/heure actuelle et de l'utilisateur connecté
    $currentDateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $currentUser = $env:USERNAME

    # Affichage des informations
    Write-Host "Current Date and Time (UTC - YYYY-MM-DD HH:MM:SS formatted): $currentDateTime"
    Write-Host "Current User's Login: $currentUser"

    # Liste des écoles
    $ecoles = @("simone-veil", "robert-batinder", "jules-ferry", "robert-dedre", "louis-pasteur", "emile-zola", "louise-michel")

    # Liste des niveaux scolaire
    $niveaux = @("cp", "ce1", "ce2", "cm1", "cm2")

    # Catégories d'utilisateurs à créer dans chaque école
    $categories = @("enseignant", "direction")

    # Définition des restrictions horaires
    ## autoriser la connexion de 9h à 17h du lundi au vendredi (élèves)
    [byte[]]$hours_eleve = @(0, 0, 0, 0, 254, 0, 0, 254, 0, 0, 254, 0, 0, 254, 0, 0, 254, 0, 0, 0, 0)

    ## autoriser la connexion de 8h à 18h du lundi au vendredi (professeurs)           
    [byte[]]$hours_professeur = @(0, 0, 0, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 0, 0)

    ## autoriser la connexion de 6h à 20h du lundi au vendredi (administratifs)
    [byte[]]$hours_administratif = @(0, 0, 0, 0, 255, 15, 0, 255, 15, 0, 255, 15, 0, 255, 15, 0, 255, 15, 0, 0, 0)

    # Pour compatibilité avec le code existant
    $hours_enseignant = $hours_professeur

    # Essayer de récupérer le chemin du domaine
    try {
        $domainDN = (Get-ADDomain -ErrorAction Stop).DistinguishedName
    }
    catch {
        Write-Host "ERREUR: Impossible de récupérer les informations du domaine. Assurez-vous que ce serveur est un contrôleur de domaine Active Directory." -ForegroundColor Red
        return @{
            Status  = "Error"
            Message = "Impossible de récupérer les informations du domaine"
        }
    }

    # Fonction de journalisation
    function WriteLog {
        param(
            [string]$Message,
            [string]$Type = "INFO"
        )
        $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "[$date] [$currentUser] [$Type] $Message"
        switch ($Type) {
            "ERROR" { Write-Host $logMessage -ForegroundColor Red }
            "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
            default { Write-Host $logMessage -ForegroundColor White }
        }
        
        # Écrire dans le fichier de log
        $logMessage | Out-File -Append -FilePath $LogPath
    }

    # SECTION: Création des 3 OUs principales avec restrictions horaires
    WriteLog "Création des 3 OUs principales avec restrictions horaires" "INFO"

    # Fonction pour créer une OU si elle n'existe pas
    function Create-OUWithRestrictions {
        param (
            [string]$OUName,
            [byte[]]$LogonHours,
            [string]$Description
        )
        
        WriteLog "Création de l'OU '$OUName'..." "INFO"
        
        # Vérifier si l'OU existe déjà
        $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue
        
        if ($ouExists) {
            WriteLog "L'OU '$OUName' existe déjà." "WARNING"
            return $ouExists
        }
        else {
            try {
                # Créer l'OU
                $ou = New-ADOrganizationalUnit -Name $OUName -Path $domainDN -Description $Description -ProtectedFromAccidentalDeletion $true -PassThru
                WriteLog "OU '$OUName' créée avec succès." "SUCCESS"
                return $ou
            } 
            catch {
                WriteLog "ERREUR lors de la création de l'OU '$OUName': $_" "ERROR"
                return $null
            }
        }
    }

    # Créer les 3 OUs principales
    $ouEleve = Create-OUWithRestrictions -OUName "Eleves" -LogonHours $hours_eleve -Description "Élèves - Heures de connexion: 09h-17h (Lun-Ven)"
    $ouProfesseur = Create-OUWithRestrictions -OUName "Professeurs" -LogonHours $hours_professeur -Description "Professeurs - Heures de connexion: 08h-18h (Lun-Ven)"
    $ouAdministratif = Create-OUWithRestrictions -OUName "Administratifs" -LogonHours $hours_administratif -Description "Administratifs - Heures de connexion: 06h-20h (Lun-Ven)"

    WriteLog "Les 3 OUs principales ont été créées avec succès." "SUCCESS"

    # SECTION: Création des sous-OUs pour chaque école
    foreach ($ecole in $ecoles) {
        # Créer une OU pour l'école dans l'OU Eleves
        $ecoleOUPath = "OU=Eleves,$domainDN"
        $ecoleOU = Get-ADOrganizationalUnit -Filter "Name -eq '$ecole'" -SearchBase $ecoleOUPath -ErrorAction SilentlyContinue
        
        if (-not $ecoleOU) {
            try {
                New-ADOrganizationalUnit -Name $ecole -Path $ecoleOUPath -Description "École $ecole - Élèves" -ProtectedFromAccidentalDeletion $true
                WriteLog "OU '$ecole' créée dans OU=Eleves." "SUCCESS"
            }
            catch {
                WriteLog "ERREUR lors de la création de l'OU '$ecole' dans OU=Eleves: $_" "ERROR"
            }
        }
        
        # Créer une OU pour l'école dans l'OU Professeurs
        $ecoleOUPath = "OU=Professeurs,$domainDN"
        $ecoleOU = Get-ADOrganizationalUnit -Filter "Name -eq '$ecole'" -SearchBase $ecoleOUPath -ErrorAction SilentlyContinue
        
        if (-not $ecoleOU) {
            try {
                New-ADOrganizationalUnit -Name $ecole -Path $ecoleOUPath -Description "École $ecole - Professeurs" -ProtectedFromAccidentalDeletion $true
                WriteLog "OU '$ecole' créée dans OU=Professeurs." "SUCCESS"
            }
            catch {
                WriteLog "ERREUR lors de la création de l'OU '$ecole' dans OU=Professeurs: $_" "ERROR"
            }
        }
    }

    # Fonction pour vérifier un groupe et le retourner ou le créer
    function Get-OrCreateGroup {
        param (
            [string]$GroupName,
            [string]$OUPath
        )
        
        # Vérification de l'existence du groupe
        $group = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
        
        if ($group) {
            WriteLog "Le groupe $GroupName existe déjà." "INFO"
            return $group
        }
        else {
            try {
                # Créer le groupe
                $group = New-ADGroup -Name $GroupName -GroupCategory Security -GroupScope Global -Path $OUPath -PassThru
                WriteLog "Groupe $GroupName créé avec succès." "SUCCESS"
                return $group
            }
            catch {
                WriteLog "ERREUR lors de la création du groupe $GroupName : $_" "ERROR"
                return $null
            }
        }
    }

    # SECTION: Appliquer les restrictions horaires aux utilisateurs existants
    WriteLog "Application des restrictions horaires aux utilisateurs existants..." "INFO"

    # Pour les élèves
    foreach ($ecole in $ecoles) {
        foreach ($niveau in $niveaux) {
            # Nom du groupe basé sur l'école et du niveau
            $nomGroupe = "${niveau}-${ecole}"
            $group = Get-ADGroup -Filter "Name -eq '$nomGroupe'" -ErrorAction SilentlyContinue
            
            if ($group) {
                $members = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.objectClass -eq 'user' }
                foreach ($member in $members) {
                    Set-ADUser -Identity $member.distinguishedName -Replace @{logonhours = $hours_eleve }
                    WriteLog "Heures de connexion mises à jour pour $($member.SamAccountName)." "INFO"
                }
            }
            else {
                # Créer le groupe s'il n'existe pas
                $ouPath = "OU=$ecole,OU=Eleves,$domainDN"
                $group = Get-OrCreateGroup -GroupName $nomGroupe -OUPath $ouPath
                WriteLog "Groupe $nomGroupe vérifié ou créé." "SUCCESS"
            }
        }
    }

    # Pour les enseignants/direction
    foreach ($ecole in $ecoles) {
        foreach ($categorie in $categories) {
            # Nom du groupe basé sur l'école et la catégorie
            $nomGroupe = "${categorie}-${ecole}"
            $group = Get-ADGroup -Filter "Name -eq '$nomGroupe'" -ErrorAction SilentlyContinue
            
            if ($group) {
                $members = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.objectClass -eq 'user' }
                foreach ($member in $members) {
                    Set-ADUser -Identity $member.distinguishedName -Replace @{logonhours = $hours_enseignant }
                    WriteLog "Heures de connexion mises à jour pour $($member.SamAccountName)." "INFO"
                }
            }
            else {
                # Créer le groupe s'il n'existe pas
                $ouPath = "OU=$ecole,OU=Professeurs,$domainDN"
                $group = Get-OrCreateGroup -GroupName $nomGroupe -OUPath $ouPath
                WriteLog "Groupe $nomGroupe vérifié ou créé." "SUCCESS"
            }
        }
    }

    # Créer un groupe pour les administratifs s'il n'existe pas déjà
    $adminGroupName = "administratifs-mediaschool"
    $adminGroup = Get-ADGroup -Filter "Name -eq '$adminGroupName'" -ErrorAction SilentlyContinue

    if (-not $adminGroup) {
        try {
            $adminGroup = New-ADGroup -Name $adminGroupName -GroupCategory Security -GroupScope Global -Path "OU=Administratifs,$domainDN" -PassThru
            WriteLog "Groupe $adminGroupName créé avec succès." "SUCCESS"
        }
        catch {
            WriteLog "ERREUR lors de la création du groupe $adminGroupName : $_" "ERROR"
        }
    }
    else {
        $members = Get-ADGroupMember -Identity $adminGroup -Recursive | Where-Object { $_.objectClass -eq 'user' }
        foreach ($member in $members) {
            Set-ADUser -Identity $member.distinguishedName -Replace @{logonhours = $hours_administratif }
            WriteLog "Heures de connexion mises à jour pour $($member.SamAccountName)." "INFO"
        }
    }

    # SECTION: Générer des données utilisateurs fictives pour un fichier CSV
    WriteLog "Génération de données utilisateurs fictives pour le fichier CSV..." "INFO"

    # Liste de prénoms et noms fictifs pour la génération d'utilisateurs
    $prenoms = @("Jean", "Marie", "Pierre", "Sophie", "Thomas", "Isabelle", "Philippe", "Nathalie", "François", "Claire", 
        "Michel", "Julie", "David", "Laura", "Nicolas", "Emilie", "Julien", "Camille", "Alexandre", "Sarah")
                
    $noms = @("Martin", "Bernard", "Dubois", "Thomas", "Robert", "Richard", "Petit", "Durand", "Leroy", "Moreau", 
        "Simon", "Laurent", "Lefebvre", "Michel", "Garcia", "David", "Bertrand", "Roux", "Vincent", "Fournier")

    # Fonction pour générer un mot de passe aléatoire
    function Generate-Password {
        param (
            [int]$Length = 12
        )
        
        $charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?'
        $random = New-Object System.Random
        $password = 1..$Length | ForEach-Object { $charSet[$random.Next(0, $charSet.Length)] }
        return -join $password
    }

    # Tableau pour stocker les utilisateurs fictifs
    $fakeUsers = @()

    # Générer des utilisateurs élèves fictifs
    foreach ($ecole in $ecoles) {
        foreach ($niveau in $niveaux) {
            # Nom du groupe
            $nomGroupe = "${niveau}-${ecole}"
            
            # OU Path pour ce groupe (CORRIGÉ - Maintenant nous utilisons un chemin compatible avec New-ADUser)
            $ouPath = "OU=$ecole,OU=Eleves,$domainDN"
            
            # Générer 3 utilisateurs par groupe
            for ($i = 1; $i -le 3; $i++) {
                $prenom = $prenoms | Get-Random
                $nom = $noms | Get-Random
                $samAccountName = "$($prenom.ToLower()).$($nom.ToLower())$i"
                $password = Generate-Password
                
                $fakeUsers += [PSCustomObject]@{
                    Prenom          = $prenom
                    Nom             = $nom
                    SamAccountName  = $samAccountName
                    Email           = "$samAccountName@mediaschool.local"
                    Password        = $password
                    Groupe          = $nomGroupe
                    OUPath          = $ouPath  # CORRIGÉ - Nom du champ changé de OU à OUPath
                    Categorie       = "Eleve"
                    HeuresConnexion = "09h-17h"
                }
            }
        }
    }

    # Générer des utilisateurs enseignants/direction fictifs
    foreach ($ecole in $ecoles) {
        foreach ($categorie in $categories) {
            # Nom du groupe
            $nomGroupe = "${categorie}-${ecole}"
            
            # OU Path pour ce groupe (CORRIGÉ - Maintenant nous utilisons un chemin compatible avec New-ADUser)
            $ouPath = "OU=$ecole,OU=Professeurs,$domainDN"
            
            # Générer 2 utilisateurs par groupe
            for ($i = 1; $i -le 2; $i++) {
                $prenom = $prenoms | Get-Random
                $nom = $noms | Get-Random
                $samAccountName = "$($prenom.ToLower()).$($nom.ToLower())$i"
                $password = Generate-Password
                
                $fakeUsers += [PSCustomObject]@{
                    Prenom          = $prenom
                    Nom             = $nom
                    SamAccountName  = $samAccountName
                    Email           = "$samAccountName@mediaschool.local"
                    Password        = $password
                    Groupe          = $nomGroupe
                    OUPath          = $ouPath  # CORRIGÉ - Nom du champ changé de OU à OUPath
                    Categorie       = $categorie
                    HeuresConnexion = "08h-18h"
                }
            }
        }
    }

    # Générer des utilisateurs administratifs fictifs
    for ($i = 1; $i -le 3; $i++) {
        $prenom = $prenoms | Get-Random
        $nom = $noms | Get-Random
        $samAccountName = "$($prenom.ToLower()).$($nom.ToLower())$i"
        $password = Generate-Password
        
        $fakeUsers += [PSCustomObject]@{
            Prenom          = $prenom
            Nom             = $nom
            SamAccountName  = $samAccountName
            Email           = "$samAccountName@mediaschool.local"
            Password        = $password
            Groupe          = "administratifs-mediaschool"
            OUPath          = "OU=Administratifs,$domainDN"  # CORRIGÉ - Nom du champ changé de OU à OUPath
            Categorie       = "Administratif"
            HeuresConnexion = "06h-20h"
        }
    }

    # Exporter les utilisateurs fictifs dans un fichier CSV
    $fakeUsers | Export-Csv -Path $OutputCSVPath -Delimiter ";" -NoTypeInformation -Encoding UTF8
    WriteLog "Données utilisateurs fictives exportées dans $OutputCSVPath" "SUCCESS"

    # Message de fin d'exécution
    WriteLog "Script terminé avec succès à $((Get-Date).ToString('HH:mm:ss')) par $currentUser." "SUCCESS"
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    Write-Host "Le fichier CSV avec les données utilisateurs fictives a été créé." -ForegroundColor Green
    Write-Host "Emplacement: $OutputCSVPath" -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    
    # Retourner un objet avec les informations importantes
    return @{
        Status         = "Success"
        LogFile        = $LogPath
        CSVFile        = $OutputCSVPath
        UsersGenerated = $fakeUsers.Count
        CreatedTime    = $currentDateTime
        ExecutedBy     = $currentUser
    }
}

# Si le script est exécuté directement (pas importé comme module)
if ($MyInvocation.InvocationName -ne '.') {
    Set-HorraireGPO
}