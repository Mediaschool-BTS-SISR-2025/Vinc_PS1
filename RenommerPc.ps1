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

function TestAdminRights {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function TestComputerName {
    param([string]$Name)
    return $Name -match '^[a-zA-Z0-9-]{1,15}$'
}

function RenommerPC {
    if (-not (TestAdminRights)) {
        WriteLog "Droits administrateur requis pour renommer le PC" -Type "ERROR"
        return
    }

    try {
        $newName = Read-Host "Entrez le nouveau nom du PC"
        
        if (-not (TestComputerName $newName)) {
            WriteLog "Nom de PC invalide. Utilisez uniquement des lettres, chiffres et tirets (max 15 caractères)" -Type "ERROR"
            return
        }

        $currentName = $env:COMPUTERNAME
        if ($currentName -eq $newName) {
            WriteLog "Le PC porte déjà ce nom" -Type "WARNING"
            return
        }

        Rename-Computer -NewName $newName -Force
        WriteLog "Nom du PC changé de '$currentName' en '$newName'. Redémarrage requis." -Type "SUCCESS"
    }
    catch {
        WriteLog "Erreur lors du renommage: $_" -Type "ERROR"
    }
}

RenommerPC