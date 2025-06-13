# Script AjoutOU tout-en-un (sans dépendances externes)
# ----------------------------------------------------

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

function TestOUName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9- ]+$' -and $Name.Length -le 64
}

# Fonction principale
function AjouterOU {
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

        $ouName = Read-Host "Nom de l'OU"
        if (-not (TestOUName $ouName)) {
            WriteLog "Nom d'OU invalide. Utilisez uniquement des lettres, chiffres, espaces et tirets (max 64 caractères)" -Type "ERROR"
            return
        }

        # Récupérer le Distinguished Name du domaine
        $domainDN = (Get-ADDomain).DistinguishedName
        
        # Vérification si l'OU existe déjà
        if (Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $domainDN -ErrorAction SilentlyContinue) {
            WriteLog "Une OU avec ce nom existe déjà" -Type "ERROR"
            return
        }

        # Création de l'OU à la racine du domaine
        WriteLog "Création de l'OU en cours..." -Type "INFO"
        New-ADOrganizationalUnit -Name $ouName -Path $domainDN -ProtectedFromAccidentalDeletion $true
        WriteLog "OU '$ouName' créée avec succès" -Type "SUCCESS"
    }
    catch {
        WriteLog "Erreur lors de la création de l'OU: $_" -Type "ERROR"
    }
}

# Exécuter la fonction
AjouterOU