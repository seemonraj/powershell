#####################################
#Install Adobe Reader using Winget
#####################################

$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
if ($ResolveWingetPath){
$WingetPath = $ResolveWingetPath[-1].Path
}

$config
Set-Location $wingetpath 
.\winget.exe install --exact --id Adobe.Acrobat.Reader.64-bit --silent --accept-package-agreements --accept-source-agreements --scope machine