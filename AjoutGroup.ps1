# Script AjoutGroup tout-en-un (sans dépendances externes)
# -------------------------------------------------------

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

function TestGroupName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9- ]+$' -and $Name.Length -le 64
}

# Fonction principale
function AjouterGroupe {
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

        $groupName = Read-Host "Nom du groupe"
        if (-not (TestGroupName $groupName)) {
            WriteLog "Nom de groupe invalide. Utilisez uniquement des lettres, chiffres, espaces et tirets (max 64 caractères)" -Type "ERROR"
            return
        }

        # Vérification si le groupe existe déjà
        if (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue) {
            WriteLog "Un groupe avec ce nom existe déjà" -Type "ERROR"
            return
        }

        # Création du groupe directement dans la structure par défaut
        WriteLog "Création du groupe en cours..." -Type "INFO"
        New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security
        WriteLog "Groupe '$groupName' créé avec succès" -Type "SUCCESS"
    }
    catch {
        WriteLog "Erreur lors de la création du groupe: $_" -Type "ERROR"
    }
}

# Exécuter la fonction
AjouterGroupe