<#
.NOTES
    Created By: Seemonraj S
    Date      : 03/02/2023
    File Name : SNET-SCR-Teams-New-Install.ps1
#>

$LogPath = "$env:windir\Temp"
if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    Start-Transcript -Path "$($LogPath)\Teams-New-Install.log" -Force
}
#Source Download URL
$DownloadURL = "https://statics.teams.cdn.office.net/production-teamsprovision/lkg/teamsbootstrapper.exe"
#Destination File
$Destination = "$env:windir\Temp\teamsbootstrapper.exe"
#Download the file to local machine
Write-Host "Downloading the installer"
Invoke-WebRequest -Uri $DownloadURL -OutFile $Destination
Write-Host "Installer has been downloaed to the local machine"

#Install Teams using Bootstrapper

If ($Destination)
{
Try
{
& $Destination -p
Write-Host "New Teams has been installed successfully"
}
Catch
{
Write-Error $_.
}
}
Else 
{
Write-Host "Teams bootstrapper file is not found"
}
Stop-Transcript
