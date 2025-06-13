# Menu principal pour la configuration Active Directory
# main.ps1
# Date: 2025-06-13
# Auteur: Vinceadr

# Configuration de l'encodage pour les caractères accentués
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# FONCTION WriteLog AUTONOME
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
        "ImportCSV.ps1",
        "HorraireGPO.ps1"  # Nom corrigé ici avec un "e"
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

function ExecuterHorraireGPO {
    $scriptPath = Join-Path $PSScriptRoot "HorraireGPO.ps1"  # Nom corrigé ici avec un "e"
    
    if (Test-Path $scriptPath) {
        try {
            WriteLog "Exécution du script: HorraireGPO.ps1" -Type "INFO"
            
            # Inclure le script HorraireGPO.ps1 pour pouvoir utiliser ses fonctions
            . $scriptPath
            
            # Exécuter la fonction Set-HorraireGPO qui est définie dans HorraireGPO.ps1
            $csvOutputPath = "$PSScriptRoot\utilisateurs_fictifs.csv"
            $result = Set-HorraireGPO -LogPath "$PSScriptRoot\HorraireGPO_log.txt" -OutputCSVPath $csvOutputPath
            
            if ($result.Status -eq "Success") {
                WriteLog "Configuration des OUs et restrictions horaires terminée avec succès" -Type "SUCCESS"
                WriteLog "$($result.UsersGenerated) utilisateurs générés dans le CSV" -Type "INFO"
                
                # Demander à l'utilisateur s'il souhaite importer le CSV
                Write-Host ""
                $importChoice = Read-Host "Voulez-vous importer les utilisateurs du CSV généré? (O/N)"
                
                if ($importChoice.ToUpper() -eq "O") {
                    WriteLog "Lancement de l'import CSV..." -Type "INFO"
                    ExecuterScript "ImportCSV.ps1"
                }
            }
            else {
                WriteLog "Erreur lors de la configuration des OUs et restrictions horaires" -Type "ERROR"
            }
        }
        catch {
            WriteLog "Erreur lors de l'exécution de HorraireGPO.ps1 : $_" -Type "ERROR"
        }
    }
    else {
        WriteLog "Script manquant: HorraireGPO.ps1" -Type "ERROR"
        Write-Host "Le script HorraireGPO.ps1 n'existe pas dans le répertoire courant." -ForegroundColor Red
    }
}

WriteLog "Démarrage du menu principal" -Type "INFO"
VerifierScripts

$continue = $true

while ($continue) {
    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host "                    MENU DE CONFIGURATION ACTIVE DIRECTORY                  " -ForegroundColor Red
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "--------------------------- Configuration de base ------------------------" -ForegroundColor Green
    Write-Host "  1 - Renommer PC" -ForegroundColor White
    Write-Host "  2 - Adressage IP fixe" -ForegroundColor White
    Write-Host "  3 - Installation ADDS, DHCP et DNS" -ForegroundColor White
    Write-Host ""
    Write-Host "------------------------ Configuration du domaine ---------------------" -ForegroundColor Green
    Write-Host "  4 - Configuration du ADDS" -ForegroundColor White
    Write-Host "  5 - Configuration du DNS" -ForegroundColor White
    Write-Host "  6 - Configuration du DHCP" -ForegroundColor White
    Write-Host ""
    Write-Host "------------ Configuration Active Directory et utilisateurs -----------" -ForegroundColor Green
    Write-Host "  7 - Ajout d'une OU" -ForegroundColor White
    Write-Host "  8 - Ajout d'un groupe d'utilisateurs" -ForegroundColor White
    Write-Host "  9 - Ajouter un utilisateur" -ForegroundColor White
    Write-Host " 10 - Import depuis un CSV" -ForegroundColor White
    Write-Host ""
    Write-Host "-------------- Configuration avancée et automatisations --------------" -ForegroundColor Green
    Write-Host " 11 - Configuration des restrictions horaires (HorraireGPO)" -ForegroundColor White  # Nom corrigé ici avec un "e"
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host "  0 - Quitter" -ForegroundColor Red
    Write-Host "============================================================================" -ForegroundColor Green
    Write-Host ""

    $choix = Read-Host "Entrez votre choix (0-11)"
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
        "11" { ExecuterHorraireGPO }  # Appel à la fonction qui gère HorraireGPO
        "0" {
            WriteLog "Fermeture du menu principal" -Type "INFO"
            Write-Host "Fermeture du menu. À bientôt !" -ForegroundColor Green
            $continue = $false
        }
        default {
            Write-Host "Choix invalide. Veuillez entrer un nombre entre 0 et 11." -ForegroundColor Red
        }
    }

    if ($continue) {
        Write-Host ""
        Write-Host "Appuyez sur une touche pour continuer..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

WriteLog "Fin du menu principal" -Type "INFO"