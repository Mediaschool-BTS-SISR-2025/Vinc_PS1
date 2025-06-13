# Chargement des fonctions utilitaires
$utilFilePath = Join-Path $PSScriptRoot "FonctionsUtilitaires.ps1" 
if (Test-Path $utilFilePath) {
    . $utilFilePath
}
else {
    Write-Host "[ERREUR] Fichier FonctionsUtilitaires.ps1 non trouvé à l'emplacement: $utilFilePath" -ForegroundColor Red
    Read-Host "Appuyez sur Entrée pour continuer..."
    exit 1
}