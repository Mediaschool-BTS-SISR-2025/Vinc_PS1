# Script pour installer les rôles Windows Server
# InstallerRoles.ps1
# Date: 2025-05-23

# Fonctions utilitaires intégrées (autonome)
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
        $scriptPath = Get-Location
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

function TestWindowsServer {
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem
        return $os.ProductType -eq 2 -or $os.ProductType -eq 3
    }
    catch {
        WriteLog "Erreur lors de la vérification du type d'OS: $_" -Type "ERROR"
        return $false
    }
}

function InstallerRoles {
    WriteLog "Début de l'installation des rôles Windows Server" -Type "INFO"
    
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour installer les rôles" -Type "ERROR"
        return
    }

    if (-not (TestWindowsServer)) {
        WriteLog "Cette fonction nécessite Windows Server" -Type "ERROR"
        return
    }

    try {
        WriteLog "Vérification des rôles et fonctionnalités existants..." -Type "INFO"
        
        # Vérification des rôles existants
        $rolesExistants = Get-WindowsFeature | Where-Object { $_.InstallState -eq "Installed" }
        $rolesNecessaires = @("AD-Domain-Services", "DHCP", "DNS")
        
        Write-Host "État actuel des rôles:" -ForegroundColor Yellow
        foreach ($role in $rolesNecessaires) {
            $roleInfo = Get-WindowsFeature -Name $role
            $status = if ($roleInfo.InstallState -eq "Installed") { "INSTALLÉ" } else { "NON INSTALLÉ" }
            $color = if ($roleInfo.InstallState -eq "Installed") { "Green" } else { "Red" }
            Write-Host "  - $($roleInfo.DisplayName): $status" -ForegroundColor $color
            
            if ($roleInfo.InstallState -eq "Installed") {
                WriteLog "Le rôle $($roleInfo.DisplayName) est déjà installé" -Type "WARNING"
            }
        }

        Write-Host ""
        $confirm = Read-Host "Voulez-vous continuer l'installation des rôles manquants ? (O/N)"
        if ($confirm -ne "O" -and $confirm -ne "o" -and $confirm -ne "Oui" -and $confirm -ne "oui") {
            WriteLog "Installation annulée par l'utilisateur" -Type "INFO"
            return
        }

        # Installation des rôles manquants
        $rolesToInstall = @()
        foreach ($role in $rolesNecessaires) {
            $roleInfo = Get-WindowsFeature -Name $role
            if ($roleInfo.InstallState -ne "Installed") {
                $rolesToInstall += $role
            }
        }

        if ($rolesToInstall.Count -eq 0) {
            WriteLog "Tous les rôles nécessaires sont déjà installés" -Type "SUCCESS"
            return
        }

        WriteLog "Installation des rôles: $($rolesToInstall -join ', ')" -Type "INFO"
        Write-Host "Installation en cours, cela peut prendre plusieurs minutes..." -ForegroundColor Yellow
        
        $result = Install-WindowsFeature -Name $rolesToInstall -IncludeManagementTools -ErrorAction Stop
        
        # Vérification post-installation
        WriteLog "Vérification post-installation..." -Type "INFO"
        $rolesInstalles = Get-WindowsFeature | Where-Object { $_.InstallState -eq "Installed" }
        $success = $true
        
        foreach ($role in $rolesToInstall) {
            $roleInfo = Get-WindowsFeature -Name $role
            if ($roleInfo.InstallState -eq "Installed") {
                WriteLog "Rôle $($roleInfo.DisplayName) installé avec succès" -Type "SUCCESS"
            }
            else {
                WriteLog "Échec de l'installation du rôle $($roleInfo.DisplayName)" -Type "ERROR"
                $success = $false
            }
        }

        if ($success) {
            WriteLog "Tous les rôles ont été installés avec succès" -Type "SUCCESS"
            
            if ($result.RestartNeeded -eq "Yes") {
                WriteLog "Un redémarrage est nécessaire pour finaliser l'installation" -Type "WARNING"
                Write-Host ""
                $restart = Read-Host "Voulez-vous redémarrer maintenant ? (O/N)"
                if ($restart -eq "O" -or $restart -eq "o" -or $restart -eq "Oui" -or $restart -eq "oui") {
                    WriteLog "Redémarrage du système en cours..." -Type "INFO"
                    Start-Sleep -Seconds 2
                    Restart-Computer -Force
                }
                else {
                    WriteLog "Redémarrage reporté - N'oubliez pas de redémarrer pour finaliser l'installation" -Type "WARNING"
                }
            }
        }
        else {
            WriteLog "Certains rôles n'ont pas pu être installés" -Type "ERROR"
        }
    }
    catch {
        WriteLog "Erreur lors de l'installation des rôles: $_" -Type "ERROR"
        Write-Host "Détails de l'erreur: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Exécution de la fonction principale
InstallerRoles