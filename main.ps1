# Menu principal pour la configuration Active Directory
# main.ps1
# Date: 2025-05-23
# Auteur: Vinceadr

# Configuration de l'encodage pour les caractères accentués
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# FONCTION WriteLog AUTONOME (plus besoin d'import)
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
    $logMessage | Out-File -Append -FilePath "$scriptPath\config_log.txt"
}

WriteLog "Démarrage du menu principal" -Type "INFO"

function VerifierScripts {
    $scripts = @(
        "RenommerPC.ps1",
        "ConfigIPFixe.ps1",
        "InstallerRoles.ps1",
        "ConfigADDS.ps1",
        "ConfigDNS.ps1",
        "ConfigDHCP.ps1",
        "AjoutOU.ps1",
        "AjoutGroup.ps1",
        "AjoutUser.ps1",
        "ImportCSV.ps1"
        # "FonctionsUtilitaires.ps1"   <-- supprimé pour ne plus vérifier ce fichier !
    )
    
    $scriptPath = $PSScriptRoot
    $manquants = @()
    
    foreach ($script in $scripts) {
        if (-not (Test-Path -Path "$scriptPath\$script")) {
            $manquants += $script
        }
    }
    
    if ($manquants.Count -gt 0) {
        Write-Host "ATTENTION: Les scripts suivants sont manquants:" -ForegroundColor Red
        foreach ($script in $manquants) {
            Write-Host "  - $script" -ForegroundColor Red
        }
        Write-Host "Appuyez sur une touche pour continuer quand même..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return $false
    }
    
    return $true
}

function ExecuterScript {
    param([string]$ScriptName)
    
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    
    if (Test-Path $scriptPath) {
        try {
            WriteLog "Exécution du script: $ScriptName" -Type "INFO"
            & $scriptPath
        }
        catch {
            WriteLog "Erreur lors de l'exécution de $ScriptName : $_" -Type "ERROR"
        }
    }
    else {
        WriteLog "Script manquant: $ScriptName" -Type "ERROR"
        Write-Host "Le script $ScriptName n'existe pas dans le répertoire courant." -ForegroundColor Red
    }
}

WriteLog "Démarrage du menu principal" -Type "INFO"
VerifierScripts

$continue = $true

while ($continue) {
    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host "                    MENU DE CONFIGURATION ACTIVE DIRECTORY                  " -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "--------------------------- Configuration de base ------------------------" -ForegroundColor Yellow
    Write-Host "  1 - Renommer PC" -ForegroundColor White
    Write-Host "  2 - Adressage IP fixe" -ForegroundColor White
    Write-Host "  3 - Installation ADDS, DHCP et DNS" -ForegroundColor White
    Write-Host ""
    Write-Host "------------------------ Configuration du domaine ---------------------" -ForegroundColor Yellow
    Write-Host "  4 - Configuration du ADDS" -ForegroundColor White
    Write-Host "  5 - Configuration du DNS" -ForegroundColor White
    Write-Host "  6 - Configuration du DHCP" -ForegroundColor White
    Write-Host ""
    Write-Host "------------ Configuration Active Directory et utilisateurs -----------" -ForegroundColor Yellow
    Write-Host "  7 - Ajout d'une OU" -ForegroundColor White
    Write-Host "  8 - Ajout d'un groupe d'utilisateurs" -ForegroundColor White
    Write-Host "  9 - Ajouter un utilisateur" -ForegroundColor White
    Write-Host " 10 - Import depuis un CSV" -ForegroundColor White
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host "  0 - Quitter" -ForegroundColor Red
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host ""

    $choix = Read-Host "Entrez votre choix (0-10)"
    Write-Host ""

    switch ($choix) {
        "1" { ExecuterScript "RenommerPC.ps1" }
        "2" { ExecuterScript "ConfigIPFixe.ps1" }
        "3" { ExecuterScript "InstallerRoles.ps1" }
        "4" { ExecuterScript "ConfigADDS.ps1" }
        "5" { ExecuterScript "ConfigDNS.ps1" }
        "6" { ExecuterScript "ConfigDHCP.ps1" }
        "7" { ExecuterScript "AjoutOU.ps1" }
        "8" { ExecuterScript "AjoutGroup.ps1" }
        "9" { ExecuterScript "AjoutUser.ps1" }
        "10" { ExecuterScript "ImportCSV.ps1" }
        "0" {
            WriteLog "Fermeture du menu principal" -Type "INFO"
            Write-Host "Fermeture du menu. À bientôt !" -ForegroundColor Green
            $continue = $false
        }
        default {
            Write-Host "Choix invalide. Veuillez entrer un nombre entre 0 et 10." -ForegroundColor Red
        }
    }

    if ($continue) {
        Write-Host ""
        Write-Host "Appuyez sur une touche pour continuer..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

WriteLog "Fin du menu principal" -Type "INFO"