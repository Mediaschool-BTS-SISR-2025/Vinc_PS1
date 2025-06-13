# Fonctions utilitaires pour les scripts d'administration Active Directory
# FonctionsUtilitaires.ps1
# Date: 2025-06-13

# Fonction pour écrire des logs
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

    # Déterminer le chemin du script
    if ($MyInvocation.MyCommand.Path) {
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    elseif ($PSScriptRoot) {
        $scriptPath = $PSScriptRoot
    }
    else {
        $scriptPath = Get-Location
    }

    # Créer le fichier de log s'il n'existe pas
    $logFile = Join-Path $scriptPath "config_log.txt"
    if (-not (Test-Path $logFile)) {
        New-Item -Path $logFile -ItemType File -Force | Out-Null
    }

    try {
        $logMessage | Out-File -Append -FilePath $logFile -Encoding UTF8
    }
    catch {
        # Si l'écriture du log échoue, on continue sans erreur
        Write-Warning "Impossible d'écrire dans le fichier de log: $_"
    }
}

# Fonction pour vérifier les droits d'administrateur
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

# Fonction pour convertir un masque de sous-réseau en longueur de préfixe
function ConvertSubnetMaskToPrefixLength {
    param([string]$SubnetMask)
    try {
        $bytes = $SubnetMask.Split('.') | ForEach-Object { [Convert]::ToByte($_) }
        $binary = ($bytes | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
        return ($binary.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    catch {
        WriteLog "Erreur lors de la conversion du masque: $_" -Type "ERROR"
        return $null
    }
}

# Fonction pour valider un nom d'utilisateur
function TestUsername {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9-_.]+$' -and $Name.Length -le 20
}

# Fonction pour valider un nom de PC
function TestComputerName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9-]{1,15}$'
}

# Fonction pour valider une adresse IP
function TestIPAddress {
    param([string]$IP)
    if ([string]::IsNullOrWhiteSpace($IP)) {
        return $false
    }
    return $IP -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
}

# Fonction pour valider un nom de domaine
function TestDomainName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$'
}

# Fonction pour valider un nom de groupe
function TestGroupName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9- ]+$' -and $Name.Length -le 64
}

# Fonction pour valider un nom d'OU
function TestOUName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    return $Name -match '^[a-zA-Z0-9- ]+$' -and $Name.Length -le 64
}

# Fonction pour valider un mot de passe
function TestPassword {
    param([string]$Password)
    if ([string]::IsNullOrWhiteSpace($Password)) {
        return $false
    }
    return $Password -match '^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$'
}

# Fonction pour tester si Windows Server est installé
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

# Fonction pour tester le service DHCP
function TestDHCPServer {
    try {
        return Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    }
    catch {
        return $null
    }
}

# Fonction pour tester le service DNS
function TestDNSServer {
    try {
        return Get-Service -Name DNS -ErrorAction SilentlyContinue
    }
    catch {
        return $null
    }
}

# Fonction pour tester le format CSV
function TestCSVFormat {
    param([string]$Path)
    try {
        $csv = Import-Csv $Path -Encoding UTF8
        $requiredColumns = @('Name', 'Username', 'Password')
        $headerNames = ($csv | Get-Member -MemberType NoteProperty).Name
        
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $headerNames }
        if ($missingColumns) {
            WriteLog "Colonnes manquantes dans le CSV: $($missingColumns -join ', ')" -Type "ERROR"
            return $false
        }
        
        if ($csv.Count -eq 0) {
            WriteLog "Le fichier CSV est vide" -Type "ERROR"
            return $false
        }
        
        return $true
    }
    catch {
        WriteLog "Erreur lors de la lecture du CSV: $_" -Type "ERROR"
        return $false
    }
}