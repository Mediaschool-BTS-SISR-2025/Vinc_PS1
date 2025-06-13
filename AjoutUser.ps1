# Script AjoutUser tout-en-un (sans dépendances externes)
# ------------------------------------------------------

# Inclut toutes les fonctions nécessaires directement dans ce script
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
}

function TestUsername {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9-_.]+$' -and $Name.Length -le 20
}

function TestPassword {
    param([string]$Password)
    if ([string]::IsNullOrWhiteSpace($Password)) {
        return $false
    }
    # Simplifié pour éviter les erreurs
    return $Password.Length -ge 8
}

# Fonction principale
function AjouterUtilisateur {
    try {
        # Vérifier si le module Active Directory est disponible
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            WriteLog "Le module ActiveDirectory n'est pas installé sur ce serveur" -Type "ERROR"
            return
        }

        # Importer le module ActiveDirectory s'il n'est pas déjà chargé
        if (-not (Get-Module -Name ActiveDirectory)) {
            Import-Module ActiveDirectory
        }

        $username = Read-Host "Nom d'utilisateur"
        if (-not (TestUsername $username)) {
            WriteLog "Nom d'utilisateur invalide. Utilisez uniquement des lettres, chiffres, tirets, points et underscores (max 20 caractères)" -Type "ERROR"
            return
        }

        # Vérification si l'utilisateur existe déjà
        if (Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue) {
            WriteLog "Un utilisateur avec ce nom existe déjà" -Type "ERROR"
            return
        }

        $password = Read-Host "Mot de passe" -AsSecureString
        
        # Option de création sans OU spécifique (directement dans Users)
        WriteLog "Création de l'utilisateur en cours..." -Type "INFO"
        New-ADUser -Name $username -SamAccountName $username -AccountPassword $password -Enabled $true
        WriteLog "Utilisateur '$username' créé avec succès" -Type "SUCCESS"
    }
    catch {
        WriteLog "Erreur lors de la création de l'utilisateur: $_" -Type "ERROR"
    }
}

# Exécuter la fonction
AjouterUtilisateur