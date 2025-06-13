# Script de configuration DNS (autonome)
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

function TestDNSServer {
    return Get-Service -Name DNS -ErrorAction SilentlyContinue
}

function InstallDNSRole {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour installer DNS" -Type "ERROR"
        return $false
    }

    try {
        WriteLog "Installation du rôle DNS..." -Type "INFO"
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        WriteLog "Rôle DNS installé avec succès" -Type "SUCCESS"
        return $true
    }
    catch {
        WriteLog "Erreur lors de l'installation du rôle DNS: $_" -Type "ERROR"
        return $false
    }
}

function ConfigDNS {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour configurer DNS" -Type "ERROR"
        return
    }

    try {
        if (-not (TestDNSServer)) {
            WriteLog "Le service DNS n'est pas installé" -Type "ERROR"
            return
        }

        # Vérification de l'état du service DNS
        $dnsService = Get-Service -Name DNS
        if ($dnsService.Status -ne "Running") {
            WriteLog "Le service DNS n'est pas en cours d'exécution" -Type "ERROR"
            Write-Host "Voulez-vous démarrer le service DNS? (O/N)"
            $response = Read-Host
            if ($response -eq "O" -or $response -eq "o") {
                Start-Service DNS
                WriteLog "Service DNS démarré" -Type "SUCCESS"
            }
            else {
                return
            }
        }

        # Menu de configuration DNS
        Write-Host "Configuration DNS :"
        Write-Host "1. Créer une zone de recherche directe"
        Write-Host "2. Créer une zone de recherche inversée"
        Write-Host "3. Configurer les redirecteurs"
        
        $option = Read-Host "Choisissez une option"
        
        switch ($option) {
            "1" {
                $zoneName = Read-Host "Nom de la zone (ex: mondomaine.com)"
                Add-DnsServerPrimaryZone -Name $zoneName -ZoneFile "$zoneName.dns"
                WriteLog "Zone de recherche directe $zoneName créée" -Type "SUCCESS"
            }
            "2" {
                $network = Read-Host "Adresse réseau (ex: 192.168.1)"
                Add-DnsServerPrimaryZone -NetworkId "$network.0/24" -ZoneFile "$network.0.24.in-addr.arpa.dns"
                WriteLog "Zone de recherche inversée pour $network.0/24 créée" -Type "SUCCESS"
            }
            "3" {
                $forwarders = Read-Host "Serveurs DNS à utiliser comme redirecteurs (séparés par des virgules)"
                $forwarderIPs = $forwarders.Split(',') | ForEach-Object { $_.Trim() }
                Set-DnsServerForwarder -IPAddress $forwarderIPs
                WriteLog "Redirecteurs DNS configurés" -Type "SUCCESS"
            }
            default {
                WriteLog "Option invalide" -Type "ERROR"
            }
        }
    }
    catch {
        WriteLog "Erreur lors de la configuration DNS: $_" -Type "ERROR"
    }
}

function CreateForwardLookupZone {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour créer une zone DNS" -Type "ERROR"
        return
    }
    
    if (-not (TestDNSServer)) {
        WriteLog "Le service DNS n'est pas installé" -Type "ERROR"
        return
    }
    
    try {
        $zoneName = Read-Host "Nom de la zone (ex: mondomaine.com)"
        $zoneType = Read-Host "Type de zone (P pour Primaire, S pour Secondaire)"
        
        if ($zoneType -eq "P" -or $zoneType -eq "p") {
            Add-DnsServerPrimaryZone -Name $zoneName -ZoneFile "$zoneName.dns"
            WriteLog "Zone de recherche directe primaire $zoneName créée" -Type "SUCCESS"
        }
        elseif ($zoneType -eq "S" -or $zoneType -eq "s") {
            $masterServers = Read-Host "Adresses IP des serveurs maîtres (séparées par des virgules)"
            $masterIPs = $masterServers.Split(',') | ForEach-Object { $_.Trim() }
            Add-DnsServerSecondaryZone -Name $zoneName -ZoneFile "$zoneName.dns" -MasterServers $masterIPs
            WriteLog "Zone de recherche directe secondaire $zoneName créée" -Type "SUCCESS"
        }
        else {
            WriteLog "Type de zone invalide" -Type "ERROR"
        }
    }
    catch {
        WriteLog "Erreur lors de la création de la zone DNS: $_" -Type "ERROR"
    }
}

function CreateReverseLookupZone {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour créer une zone DNS inversée" -Type "ERROR"
        return
    }
    
    if (-not (TestDNSServer)) {
        WriteLog "Le service DNS n'est pas installé" -Type "ERROR"
        return
    }
    
    try {
        $network = Read-Host "Adresse réseau (ex: 192.168.1)"
        $prefix = Read-Host "Préfixe réseau (ex: 24 pour un /24)"
        
        Add-DnsServerPrimaryZone -NetworkId "$network.0/$prefix" -ZoneFile "$network.0.$prefix.in-addr.arpa.dns"
        WriteLog "Zone de recherche inversée pour $network.0/$prefix créée" -Type "SUCCESS"
    }
    catch {
        WriteLog "Erreur lors de la création de la zone DNS inversée: $_" -Type "ERROR"
    }
}

function Show-DNSConfigMenu {
    Clear-Host
    Write-Host "===== Configuration DNS =====" -ForegroundColor Cyan
    Write-Host "1. Installer le rôle DNS"
    Write-Host "2. Vérifier l'état du service DNS"
    Write-Host "3. Configurer DNS"
    Write-Host "4. Créer une zone de recherche directe"
    Write-Host "5. Créer une zone de recherche inversée"
    Write-Host "6. Vider le cache DNS"
    Write-Host "7. Retour au menu principal"
    
    $choice = Read-Host "Entrez votre choix"
    
    switch ($choice) {
        "1" {
            InstallDNSRole
            Pause
            Show-DNSConfigMenu 
        }
        "2" {
            $dnsService = Get-Service -Name DNS -ErrorAction SilentlyContinue
            if ($dnsService) {
                WriteLog "État du service DNS: $($dnsService.Status)" -Type "INFO"
                if ($dnsService.Status -ne "Running") {
                    Write-Host "Voulez-vous démarrer le service DNS? (O/N)"
                    $response = Read-Host
                    if ($response -eq "O" -or $response -eq "o") {
                        Start-Service DNS
                        WriteLog "Service DNS démarré" -Type "SUCCESS"
                    }
                }
            }
            else {
                WriteLog "Le service DNS n'est pas installé" -Type "WARNING"
            }
            Pause
            Show-DNSConfigMenu
        }
        "3" {
            ConfigDNS
            Pause
            Show-DNSConfigMenu
        }
        "4" {
            CreateForwardLookupZone
            Pause
            Show-DNSConfigMenu
        }
        "5" {
            CreateReverseLookupZone
            Pause
            Show-DNSConfigMenu
        }
        "6" {
            if (-not (TestDNSServer)) {
                WriteLog "Le service DNS n'est pas installé" -Type "ERROR"
            }
            else {
                Clear-DnsServerCache
                WriteLog "Cache DNS vidé" -Type "SUCCESS"
            }
            Pause
            Show-DNSConfigMenu
        }
        "7" { return }
        default { 
            WriteLog "Option invalide. Veuillez réessayer." -Type "ERROR" 
            Pause
            Show-DNSConfigMenu
        }
    }
}

# Exécuter la fonction de menu directement au chargement du script
Show-DNSConfigMenu