# ImportCSV.ps1
# Script pour importer des utilisateurs depuis un CSV
# Date: 2025-06-13
# Auteur: Vinceadr

# Importation du module Active Directory
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

function WriteLog {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$date] [$Type] $Message"
    switch ($Type) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor White }
    }
    if ($MyInvocation.MyCommand.Path) {
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    else {
        $scriptPath = $PWD
    }
    $logMessage | Out-File -Append -FilePath "$scriptPath\import_log.txt"
}

WriteLog "=== DÉBUT DE L'IMPORTATION D'UTILISATEURS ===" "INFO"
WriteLog "Date: $(Get-Date)" "INFO"
WriteLog "Utilisateur exécutant le script: $env:USERNAME" "INFO"

# Définir le chemin du fichier CSV
$scriptPath = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PWD }
$CSVPath = "$scriptPath\utilisateurs_fictifs.csv"
WriteLog "Chemin du fichier CSV: $CSVPath" "INFO"

# Vérifier si le fichier existe
if (-not (Test-Path $CSVPath)) {
    WriteLog "Le fichier CSV '$CSVPath' est introuvable." "ERROR"
    return
}

# Importer les utilisateurs
try {
    $users = Import-Csv -Path $CSVPath -Delimiter ";" -Encoding UTF8
    WriteLog "$($users.Count) utilisateurs trouvés dans le CSV." "INFO"
    
    foreach ($user in $users) {
        try {
            # Vérifier si les champs obligatoires sont présents
            if (-not $user.Prenom -or -not $user.Nom -or -not $user.SamAccountName) {
                WriteLog "Utilisateur ignoré : informations obligatoires manquantes." "WARNING"
                continue
            }
            
            # Vérifier si l'utilisateur existe déjà
            $existingUser = Get-ADUser -Filter "SamAccountName -eq '$($user.SamAccountName)'" -ErrorAction SilentlyContinue
            
            if ($existingUser) {
                WriteLog "L'utilisateur $($user.SamAccountName) existe déjà." "INFO"
            }
            else {
                # Créer le nouvel utilisateur
                $securePassword = ConvertTo-SecureString $user.Password -AsPlainText -Force
                
                # CORRIGÉ - Utilisation du champ OUPath au lieu de OU
                $userParams = @{
                    Name                  = "$($user.Prenom) $($user.Nom)"
                    GivenName             = $user.Prenom
                    Surname               = $user.Nom
                    SamAccountName        = $user.SamAccountName
                    UserPrincipalName     = $user.Email
                    DisplayName           = "$($user.Prenom) $($user.Nom)"
                    Enabled               = $true
                    Path                  = $user.OUPath
                    AccountPassword       = $securePassword
                    ChangePasswordAtLogon = $true
                }
                
                # Créer l'utilisateur
                New-ADUser @userParams
                WriteLog "Utilisateur $($user.SamAccountName) créé avec succès." "SUCCESS"
                
                # Appliquer les restrictions horaires selon la catégorie
                switch ($user.Categorie) {
                    "Eleve" {
                        $hours_eleve = @(0, 0, 0, 0, 254, 0, 0, 254, 0, 0, 254, 0, 0, 254, 0, 0, 254, 0, 0, 0, 0)
                        Set-ADUser -Identity $user.SamAccountName -Replace @{logonhours = $hours_eleve }
                    }
                    "enseignant" {
                        $hours_professeur = @(0, 0, 0, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 0, 0)
                        Set-ADUser -Identity $user.SamAccountName -Replace @{logonhours = $hours_professeur }
                    }
                    "direction" {
                        $hours_professeur = @(0, 0, 0, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 255, 3, 0, 0, 0)
                        Set-ADUser -Identity $user.SamAccountName -Replace @{logonhours = $hours_professeur }
                    }
                    "Administratif" {
                        $hours_administratif = @(0, 0, 0, 0, 255, 15, 0, 255, 15, 0, 255, 15, 0, 255, 15, 0, 255, 15, 0, 0, 0)
                        Set-ADUser -Identity $user.SamAccountName -Replace @{logonhours = $hours_administratif }
                    }
                }
                
                # Ajouter l'utilisateur au groupe si spécifié
                if ($user.Groupe) {
                    try {
                        Add-ADGroupMember -Identity $user.Groupe -Members $user.SamAccountName
                        WriteLog "Utilisateur $($user.SamAccountName) ajouté au groupe $($user.Groupe)." "SUCCESS"
                    }
                    catch {
                        WriteLog "Erreur lors de l'ajout de $($user.SamAccountName) au groupe $($user.Groupe): $_" "ERROR"
                    }
                }
            }
        }
        catch {
            WriteLog "Erreur lors du traitement de l'utilisateur $($user.SamAccountName) : $_" "ERROR"
        }
    }
}
catch {
    WriteLog "Erreur lors de l'importation du CSV: $_" "ERROR"
}

WriteLog "=== FIN DE L'IMPORTATION D'UTILISATEURS ===" "INFO"