# Script de configuration AD DS (contrôleur de domaine)
# Date: 2025-06-06

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
    elseif ($PSScriptRoot) {
        $scriptPath = $PSScriptRoot
    }
    else {
        $scriptPath = $PWD
    }
    $logFile = Join-Path $scriptPath "config_log.txt"
    if (-not (Test-Path $logFile)) {
        New-Item -Path $logFile -ItemType File -Force | Out-Null
    }
    try {
        $logMessage | Out-File -Append -FilePath $logFile -Encoding UTF8
    }
    catch {
        Write-Warning "Impossible d'écrire dans le fichier de log: $_"
    }
}

function TestAdminRights {
    try {
        $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        WriteLog "Erreur lors de la vérification des droits admin: $_" -Type "ERROR"
        return $false
    }
}

function TestDomainName {
    param([string]$Name)
    return $Name -match '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$'
}

function IsRebootPending {
    # Vérifie si un redémarrage Windows est en attente
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    foreach ($path in $regPaths) {
        if (Test-Path $path) { return $true }
    }
    return $false
}

function InstallADDSRole {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour installer AD DS" -Type "ERROR"
        return $false
    }

    try {
        WriteLog "Installation du rôle AD DS..." -Type "INFO"
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        WriteLog "Rôle AD DS installé avec succès" -Type "SUCCESS"
        return $true
    }
    catch {
        WriteLog "Erreur lors de l'installation du rôle AD DS: $_" -Type "ERROR"
        return $false
    }
}

function ConfigADDS {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour configurer AD DS" -Type "ERROR"
        return
    }

    if (IsRebootPending) {
        WriteLog "Un redémarrage du système est requis avant de poursuivre la configuration du contrôleur de domaine." -Type "ERROR"
        Write-Host "Veuillez redémarrer la machine puis relancer ce script."
        return
    }

    try {
        # Vérification si AD DS est déjà installé
        $addsRole = Get-WindowsFeature AD-Domain-Services
        if (-not $addsRole.Installed) {
            WriteLog "Le rôle AD DS n'est pas installé" -Type "ERROR"
            return
        }

        $domainName = Read-Host "Nom du domaine à créer (ex: monentreprise.local)"
        if (-not (TestDomainName $domainName)) {
            WriteLog "Format de nom de domaine invalide" -Type "ERROR"
            return
        }

        # Vérification de l'espace disque
        $systemDrive = (Get-Item $env:windir).PSDrive.Name
        $freeSpace = (Get-PSDrive $systemDrive).Free
        if ($freeSpace -lt 10GB) {
            WriteLog "Espace disque insuffisant. 10 Go minimum requis" -Type "ERROR"
            return
        }

        # Vérification de la mémoire RAM
        $totalRam = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        if ($totalRam -lt 2GB) {
            WriteLog "Mémoire RAM insuffisante. 2 Go minimum requis" -Type "ERROR"
            return
        }

        try {
            Install-ADDSForest -DomainName $domainName -InstallDNS -Force -NoRebootOnCompletion -ErrorAction Stop
            WriteLog "Installation du contrôleur de domaine pour $domainName terminée" -Type "SUCCESS"
        }
        catch {
            WriteLog "Erreur lors de la promotion du contrôleur de domaine : $($_.Exception.Message)" -Type "ERROR"
            Write-Host "L'installation a échoué. Vérifiez que la machine a bien été redémarrée et que toutes les conditions préalables sont remplies."
            return
        }
    }
    catch {
        WriteLog "Erreur lors de la configuration AD DS: $_" -Type "ERROR"
    }
}

function Show-ADDSConfigMenu {
    Clear-Host
    Write-Host "===== Configuration Active Directory DS =====" -ForegroundColor Cyan
    Write-Host "1. Installer le rôle AD DS"
    Write-Host "2. Configurer le contrôleur de domaine"
    Write-Host "3. Vérifier l'état du contrôleur de domaine"
    Write-Host "4. Retour au menu principal"
    
    $choice = Read-Host "Entrez votre choix"
    
    switch ($choice) {
        "1" {
            InstallADDSRole
            Pause
            Show-ADDSConfigMenu 
        }
        "2" {
            ConfigADDS
            Pause
            Show-ADDSConfigMenu
        }
        "3" {
            # Vérification de l'état du contrôleur de domaine
            $addsRole = Get-WindowsFeature AD-Domain-Services
            if ($addsRole.Installed) {
                WriteLog "Le rôle AD DS est installé" -Type "SUCCESS"
                try {
                    $domain = Get-ADDomain -ErrorAction SilentlyContinue
                    if ($domain) {
                        WriteLog "Contrôleur de domaine configuré pour le domaine: $($domain.DNSRoot)" -Type "SUCCESS"
                    }
                    else {
                        WriteLog "Le rôle AD DS est installé mais n'est pas configuré comme contrôleur de domaine" -Type "WARNING"
                    }
                }
                catch {
                    WriteLog "Le rôle AD DS est installé mais n'est pas configuré comme contrôleur de domaine" -Type "WARNING"
                }
            }
            else {
                WriteLog "Le rôle AD DS n'est pas installé" -Type "WARNING"
            }
            Pause
            Show-ADDSConfigMenu
        }
        "4" { return }
        default { 
            WriteLog "Option invalide. Veuillez réessayer." -Type "ERROR"
            Pause
            Show-ADDSConfigMenu 
        }
    }
}

# Exécuter la fonction de menu directement au chargement du script
Show-ADDSConfigMenu