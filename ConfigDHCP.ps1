# Script de configuration DHCP
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

function TestDHCPServer {
    return Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
}

function Install-DHCPRole {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour installer DHCP" -Type "ERROR"
        return $false
    }

    try {
        WriteLog "Installation du rôle DHCP..." -Type "INFO"
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
        
        # Autorisation du serveur DHCP dans Active Directory si disponible
        try {
            Add-DhcpServerInDC
            WriteLog "Serveur DHCP autorisé dans Active Directory" -Type "SUCCESS"
        }
        catch {
            WriteLog "Impossible d'autoriser le serveur DHCP dans Active Directory: $_" -Type "WARNING"
            WriteLog "Si vous n'êtes pas dans un domaine Active Directory, cette erreur est normale." -Type "INFO"
        }
        
        WriteLog "Rôle DHCP installé avec succès" -Type "SUCCESS"
        return $true
    }
    catch {
        WriteLog "Erreur lors de l'installation du rôle DHCP: $_" -Type "ERROR"
        return $false
    }
}

function Create-DHCPScope {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour créer une étendue DHCP" -Type "ERROR"
        return
    }
    
    if (-not (TestDHCPServer)) {
        WriteLog "Le service DHCP n'est pas installé" -Type "ERROR"
        return
    }
    
    try {
        $scopeName = Read-Host "Nom de l'étendue"
        $scopeDesc = Read-Host "Description de l'étendue"
        $startIP = Read-Host "Adresse IP de début"
        $endIP = Read-Host "Adresse IP de fin"
        $subnetMask = Read-Host "Masque de sous-réseau (ex: 255.255.255.0)"
        
        # Validation des adresses IP
        $ipPattern = "^([0-9]{1,3}\.){3}[0-9]{1,3}$"
        if (-not ($startIP -match $ipPattern) -or -not ($endIP -match $ipPattern) -or -not ($subnetMask -match $ipPattern)) {
            WriteLog "Format d'adresse IP invalide" -Type "ERROR"
            return
        }
        
        # Création de l'étendue DHCP
        Add-DhcpServerv4Scope -Name $scopeName -Description $scopeDesc -StartRange $startIP -EndRange $endIP -SubnetMask $subnetMask
        
        WriteLog "Étendue DHCP '$scopeName' créée avec succès" -Type "SUCCESS"
        
        # Configurer les options DHCP de base
        Write-Host "Voulez-vous configurer les options DHCP de base pour cette étendue? (O/N)"
        $response = Read-Host
        if ($response -eq "O" -or $response -eq "o") {
            $routerIP = Read-Host "Adresse IP de la passerelle par défaut"
            $dnsServers = Read-Host "Adresses IP des serveurs DNS (séparées par des virgules)"
            
            if ($routerIP -match $ipPattern) {
                Set-DhcpServerv4OptionValue -ScopeId $startIP -Router $routerIP
                WriteLog "Passerelle par défaut configurée: $routerIP" -Type "SUCCESS"
            }
            
            if ($dnsServers) {
                $dnsIPs = $dnsServers.Split(',') | ForEach-Object { $_.Trim() }
                Set-DhcpServerv4OptionValue -ScopeId $startIP -DnsServer $dnsIPs
                WriteLog "Serveurs DNS configurés: $dnsServers" -Type "SUCCESS"
            }
        }
    }
    catch {
        WriteLog "Erreur lors de la création de l'étendue DHCP: $_" -Type "ERROR"
    }
}

function Configure-DHCPOptions {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour configurer les options DHCP" -Type "ERROR"
        return
    }
    
    if (-not (TestDHCPServer)) {
        WriteLog "Le service DHCP n'est pas installé" -Type "ERROR"
        return
    }
    
    try {
        # Récupération des étendues existantes
        $scopes = Get-DhcpServerv4Scope
        
        if ($scopes.Count -eq 0) {
            WriteLog "Aucune étendue DHCP trouvée" -Type "ERROR"
            return
        }
        
        Write-Host "Étendues DHCP disponibles:"
        for ($i = 0; $i -lt $scopes.Count; $i++) {
            Write-Host "$($i+1). $($scopes[$i].Name) ($($scopes[$i].ScopeId))"
        }
        
        $scopeChoice = [int](Read-Host "Choisissez une étendue à configurer (numéro)") - 1
        
        if ($scopeChoice -lt 0 -or $scopeChoice -ge $scopes.Count) {
            WriteLog "Choix d'étendue invalide" -Type "ERROR"
            return
        }
        
        $selectedScope = $scopes[$scopeChoice]
        
        Write-Host "Options disponibles:"
        Write-Host "1. Passerelle par défaut"
        Write-Host "2. Serveurs DNS"
        Write-Host "3. Suffixe DNS"
        Write-Host "4. Serveurs WINS"
        Write-Host "5. Durée du bail"
        
        $optionChoice = Read-Host "Choisissez une option à configurer"
        
        switch ($optionChoice) {
            "1" {
                $routerIP = Read-Host "Adresse IP de la passerelle par défaut"
                Set-DhcpServerv4OptionValue -ScopeId $selectedScope.ScopeId -Router $routerIP
                WriteLog "Passerelle par défaut configurée: $routerIP pour l'étendue $($selectedScope.Name)" -Type "SUCCESS"
            }
            "2" {
                $dnsServers = Read-Host "Adresses IP des serveurs DNS (séparées par des virgules)"
                $dnsIPs = $dnsServers.Split(',') | ForEach-Object { $_.Trim() }
                Set-DhcpServerv4OptionValue -ScopeId $selectedScope.ScopeId -DnsServer $dnsIPs
                WriteLog "Serveurs DNS configurés pour l'étendue $($selectedScope.Name)" -Type "SUCCESS"
            }
            "3" {
                $dnsSuffix = Read-Host "Suffixe DNS"
                Set-DhcpServerv4OptionValue -ScopeId $selectedScope.ScopeId -DnsDomain $dnsSuffix
                WriteLog "Suffixe DNS configuré: $dnsSuffix pour l'étendue $($selectedScope.Name)" -Type "SUCCESS"
            }
            "4" {
                $winsServers = Read-Host "Adresses IP des serveurs WINS (séparées par des virgules)"
                $winsIPs = $winsServers.Split(',') | ForEach-Object { $_.Trim() }
                Set-DhcpServerv4OptionValue -ScopeId $selectedScope.ScopeId -WinsServer $winsIPs
                WriteLog "Serveurs WINS configurés pour l'étendue $($selectedScope.Name)" -Type "SUCCESS"
            }
            "5" {
                $leaseDuration = Read-Host "Durée du bail (en jours)"
                $timeSpan = New-TimeSpan -Days ([int]$leaseDuration)
                Set-DhcpServerv4Scope -ScopeId $selectedScope.ScopeId -LeaseDuration $timeSpan
                WriteLog "Durée du bail configurée à $leaseDuration jours pour l'étendue $($selectedScope.Name)" -Type "SUCCESS"
            }
            default {
                WriteLog "Option invalide" -Type "ERROR"
            }
        }
    }
    catch {
        WriteLog "Erreur lors de la configuration des options DHCP: $_" -Type "ERROR"
    }
}

function Manage-DHCPReservations {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour gérer les réservations DHCP" -Type "ERROR"
        return
    }
    
    if (-not (TestDHCPServer)) {
        WriteLog "Le service DHCP n'est pas installé" -Type "ERROR"
        return
    }
    
    try {
        # Récupération des étendues existantes
        $scopes = Get-DhcpServerv4Scope
        
        if ($scopes.Count -eq 0) {
            WriteLog "Aucune étendue DHCP trouvée" -Type "ERROR"
            return
        }
        
        Write-Host "Étendues DHCP disponibles:"
        for ($i = 0; $i -lt $scopes.Count; $i++) {
            Write-Host "$($i+1). $($scopes[$i].Name) ($($scopes[$i].ScopeId))"
        }
        
        $scopeChoice = [int](Read-Host "Choisissez une étendue (numéro)") - 1
        
        if ($scopeChoice -lt 0 -or $scopeChoice -ge $scopes.Count) {
            WriteLog "Choix d'étendue invalide" -Type "ERROR"
            return
        }
        
        $selectedScope = $scopes[$scopeChoice]
        
        Write-Host "Gestion des réservations pour l'étendue $($selectedScope.Name):"
        Write-Host "1. Ajouter une réservation"
        Write-Host "2. Supprimer une réservation"
        Write-Host "3. Lister les réservations existantes"
        
        $resChoice = Read-Host "Entrez votre choix"
        
        switch ($resChoice) {
            "1" {
                $ipAddress = Read-Host "Adresse IP à réserver"
                $macAddress = Read-Host "Adresse MAC du client (format: 00-11-22-33-44-55)"
                $clientName = Read-Host "Nom du client"
                
                Add-DhcpServerv4Reservation -ScopeId $selectedScope.ScopeId -IPAddress $ipAddress -ClientId $macAddress -Name $clientName
                WriteLog "Réservation ajoutée pour $clientName ($ipAddress)" -Type "SUCCESS"
            }
            "2" {
                # Affichage des réservations existantes
                $reservations = Get-DhcpServerv4Reservation -ScopeId $selectedScope.ScopeId
                
                if ($reservations.Count -eq 0) {
                    WriteLog "Aucune réservation trouvée pour cette étendue" -Type "WARNING"
                    return
                }
                
                for ($i = 0; $i -lt $reservations.Count; $i++) {
                    Write-Host "$($i+1). $($reservations[$i].Name) ($($reservations[$i].IPAddress))"
                }
                
                $resIndex = [int](Read-Host "Choisissez une réservation à supprimer (numéro)") - 1
                
                if ($resIndex -lt 0 -or $resIndex -ge $reservations.Count) {
                    WriteLog "Choix de réservation invalide" -Type "ERROR"
                    return
                }
                
                Remove-DhcpServerv4Reservation -ScopeId $selectedScope.ScopeId -ClientId $reservations[$resIndex].ClientId -Force
                WriteLog "Réservation pour $($reservations[$resIndex].Name) supprimée" -Type "SUCCESS"
            }
            "3" {
                $reservations = Get-DhcpServerv4Reservation -ScopeId $selectedScope.ScopeId
                
                if ($reservations.Count -eq 0) {
                    WriteLog "Aucune réservation trouvée pour cette étendue" -Type "WARNING"
                    return
                }
                
                Write-Host "Réservations dans l'étendue $($selectedScope.Name):"
                foreach ($res in $reservations) {
                    Write-Host "Nom: $($res.Name)"
                    Write-Host "  IP: $($res.IPAddress)"
                    Write-Host "  MAC: $($res.ClientId)"
                    Write-Host "  Description: $($res.Description)"
                    Write-Host "------------------------------"
                }
            }
            default {
                WriteLog "Option invalide" -Type "ERROR"
            }
        }
    }
    catch {
        WriteLog "Erreur lors de la gestion des réservations DHCP: $_" -Type "ERROR"
    }
}

function Toggle-DHCPService {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour gérer le service DHCP" -Type "ERROR"
        return
    }
    
    try {
        $dhcpService = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
        
        if (-not $dhcpService) {
            WriteLog "Le service DHCP n'est pas installé" -Type "ERROR"
            return
        }
        
        $status = $dhcpService.Status
        
        if ($status -eq "Running") {
            Stop-Service -Name DHCPServer
            WriteLog "Service DHCP arrêté" -Type "WARNING"
        }
        else {
            Start-Service -Name DHCPServer
            WriteLog "Service DHCP démarré" -Type "SUCCESS"
        }
    }
    catch {
        WriteLog "Erreur lors de la gestion du service DHCP: $_" -Type "ERROR"
    }
}

function Show-DHCPConfigMenu {
    Clear-Host
    Write-Host "===== Configuration DHCP =====" -ForegroundColor Cyan
    Write-Host "1. Installer le rôle DHCP"
    Write-Host "2. Vérifier l'état du service DHCP"
    Write-Host "3. Créer une étendue DHCP"
    Write-Host "4. Configurer les options DHCP"
    Write-Host "5. Gérer les réservations"
    Write-Host "6. Activer/Désactiver le service DHCP"
    Write-Host "7. Retour au menu principal"
    
    $choice = Read-Host "Entrez votre choix"
    
    switch ($choice) {
        "1" {
            Install-DHCPRole
            Pause
            Show-DHCPConfigMenu
        }
        "2" {
            $dhcpService = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
            if ($dhcpService) {
                WriteLog "État du service DHCP: $($dhcpService.Status)" -Type "INFO"
                if ($dhcpService.Status -eq "Running") {
                    # Afficher les étendues actives si le service est en cours d'exécution
                    try {
                        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                        if ($scopes -and $scopes.Count -gt 0) {
                            Write-Host "`nÉtendues DHCP configurées:" -ForegroundColor Cyan
                            foreach ($scope in $scopes) {
                                Write-Host "- $($scope.Name) ($($scope.ScopeId)): $($scope.State)"
                            }
                        }
                        else {
                            Write-Host "`nAucune étendue DHCP configurée." -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-Host "`nErreur lors de la récupération des étendues: $_" -ForegroundColor Red
                    }
                }
            }
            else {
                WriteLog "Le service DHCP n'est pas installé" -Type "WARNING"
            }
            Pause
            Show-DHCPConfigMenu
        }
        "3" {
            Create-DHCPScope
            Pause
            Show-DHCPConfigMenu
        }
        "4" {
            Configure-DHCPOptions
            Pause
            Show-DHCPConfigMenu
        }
        "5" {
            Manage-DHCPReservations
            Pause
            Show-DHCPConfigMenu
        }
        "6" {
            Toggle-DHCPService
            Pause
            Show-DHCPConfigMenu
        }
        "7" { return }
        default { 
            WriteLog "Option invalide. Veuillez réessayer." -Type "ERROR" 
            Pause
            Show-DHCPConfigMenu
        }
    }
}

# Exécuter la fonction de menu directement au chargement du script
Show-DHCPConfigMenu