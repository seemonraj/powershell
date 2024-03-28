<#
- TITLE:          Microsoft Windows Virtual Desktop deployment
- AUTHORED BY:    Seemonraj S
- AUTHORED DATE:  01/27/2024
- CONTRIBUTORS:   
- LAST UPDATED:   
- PURPOSE:        To deploy an azure virtual desktop LAB using powershell
                  
- Important:      
#>

Import-Module az

#Register AVD Resource Provider

Register-AzResourceProvider -ProviderNamespace Microsoft.DesktopVirtualization

# Create a Virtual Network and subnet

New-AzResourceGroup -Name SRS-AVD-VNet-RG -Location 'West Europe' 
New-AzNetworkSecurityGroup -Name SRS-AVD-NSG -Location 'West Europe' -ResourceGroupName SRS-AVD-Vnet-RG

$vnet = @{
    Name = 'SRS-AVD-VNet'
    ResourceGroupName = 'SRS-AVD-VNet-RG'
    Location = 'westeurope'
    AddressPrefix = '10.0.0.0/16'
}
$virtualNetwork = New-AzVirtualNetwork @vnet

$subnet = @{
    Name = 'SRS-AVD-Subnet'
    VirtualNetwork = $virtualNetwork
    AddressPrefix = '10.0.0.0/24'
}
$subnetConfig = Add-AzVirtualNetworkSubnetConfig @subnet

$virtualNetwork | Set-AzVirtualNetwork

#Create The DC VM
New-AzResourceGroup -Name SRS-AVD-DC-RG -Location 'West Europe' 

New-AzVm `
    -ResourceGroupName 'SRS-AVD-DC-RG' `
    -Name 'SRSAVDDC' `
    -Location 'WestEurope' `
    -Image 'MicrosoftWindowsServer:WindowsServer:2022-datacenter:latest' `
    -VirtualNetworkName 'SRS-AVD-VNet' `
    -SubnetName 'SRS-AVD-Subnet' `
    -SecurityGroupName 'SRS-AVD-NSG' `
    -PublicIpAddressName 'SRSAVDDC-ip' `
    -OpenPorts 3389 `
    -Size Standard_B2s


################################################################

#Install DC Role (This needs to be run on the newly created VM)
################################################################

#Declare variables
$DatabasePath = "c:\windows\NTDS"
$DomainMode = "WinThreshold"
#Change the Domain name and Domain Net BIOS Name to match your public domain name
$DomainName = "SEEMON.CO.UK"
$DomainNetBIOSName = "SEEMON"
$ForestMode = "WinThreshold"
$LogPath = "c:\windows\NTDS"
$SysVolPath = "c:\windows\SYSVOL"
$Password = "Therock@123456789"

#Install AD DS, DNS and GPMC 
start-job -Name addFeature -ScriptBlock { 
Add-WindowsFeature -Name "ad-domain-services" -IncludeAllSubFeature -IncludeManagementTools 
Add-WindowsFeature -Name "dns" -IncludeAllSubFeature -IncludeManagementTools 
Add-WindowsFeature -Name "gpmc" -IncludeAllSubFeature -IncludeManagementTools } 
Wait-Job -Name addFeature 
Get-WindowsFeature | Where-Object {$_.InstallState -eq 'Installed'} | Format-Table DisplayName,Name,InstallState

#Convert Password 
$Password = ConvertTo-SecureString -String $Password -AsPlainText -Force

#Create New AD Forest
Install-ADDSForest -CreateDnsDelegation:$false -DatabasePath $DatabasePath -DomainMode $DomainMode -DomainName $DomainName `
    -SafeModeAdministratorPassword $Password -DomainNetbiosName $DomainNetBIOSName -ForestMode $ForestMode -InstallDns:$true -LogPath $LogPath -NoRebootOnCompletion:$false `
    -SysvolPath $SysVolPath -Force:$true

##################################################
# Add AD Users
##################################################

# Set values for your environment
$numUsers = "5"
$userPrefix = "SRSAVD"
$passWord = "Therock@123456789"
# Update with your custom domain name
$userDomain = "seemon.co.uk"

# Import the AD Module
Import-Module ActiveDirectory

# Convert the password to a secure string
$UserPass = ConvertTo-SecureString -AsPlainText "$passWord" -Force

#Add the users
for ($i=0; $i -le $numUsers; $i++) {
$newUser = $userPrefix + $i
New-ADUser -name $newUser -SamAccountName $newUser -UserPrincipalName $newUser@$userDomain -GivenName $newUser -Surname $newUser -DisplayName $newUser `
-AccountPassword $userPass -ChangePasswordAtLogon $false -PasswordNeverExpires $true -Enabled $true
}

#Disable IE Enhanced Security

function Disable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
}
Disable-InternetExplorerESC
function Enable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 1
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 1
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) has been enabled." -ForegroundColor Green
}
function Disable-UserAccessControl {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 00000000
    Write-Host "User Access Control (UAC) has been disabled." -ForegroundColor Green    
}
Disable-UserAccessControl

#Update the DNS Server on VNet (IP Of the DC)

$vNetRGname = "SRS-AVD-VNet-RG"
$vNet = "SRS-AVD-VNet"
$vNet = Get-AzVirtualNetwork -ResourceGroupName $vNetRGname -name $vNet
# Replace the IPs with your DNS server IPs here
$array = @("192.168.1.4")
$newObject = New-Object -type PSObject -Property @{"DnsServers" = $array}
$vNet.DhcpOptions = $newObject
$vNet | Set-AzVirtualNetwork

# Create a resource group for Custom Image Template

New-AzResourceGroup -Name 'SRS-AVD-IMG-RG' -Location 'West Europe'

# Create a Managed Identity and assign permissions for AIB

New-AzUserAssignedIdentity -Name SRS-AVD-Identity -ResourceGroupName SRS-AVD-IMG-RG -Location WestEurope

# Custom role for managed identity

$subid = "2db4252e-23cf-4159-9f1c-4e22964e4911"

# Resource group - image builder will only support creating custom images in the same Resource Group as the source managed image.
$imageResourceGroup = "SRS-AVD-IMG-RG"
$identityName = "SRS-AVD-Identity"

# Use a web request to download the sample JSON description
$JsonURI="https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
$roledefinition="aibRoleImageCreation.json"

Invoke-WebRequest -Uri $JsonURI -Outfile $roledefinition -UseBasicParsing

# Create a unique role name to avoid clashes in the same Azure Active Directory domain
$timeInt=$(get-date -UFormat "%s")
$imageRoleDefName="Azure Image Builder Image Def"+$timeInt

# Update the JSON definition placeholders with variable values
((Get-Content -path $roledefinition -Raw) -replace '<subscriptionID>',$subid) | Set-Content -Path $roledefinition
((Get-Content -path $roledefinition -Raw) -replace '<rgName>', $imageResourceGroup) | Set-Content -Path $roledefinition
((Get-Content -path $roledefinition -Raw) -replace 'Azure Image Builder Service Image Creation Role', $imageRoleDefName) | Set-Content -Path $roledefinition

# Create a custom role from the aibRoleImageCreation.json description file. 
New-AzRoleDefinition -InputFile $roledefinition

# Get the user-identity properties
$identityNameResourceId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).Id
$identityNamePrincipalId=$(Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroup -Name $identityName).PrincipalId

# Grant the custom role to the user-assigned managed identity for Azure Image Builder.
$parameters = @{
    ObjectId = $identityNamePrincipalId
    RoleDefinitionName = $imageRoleDefName
    Scope = '/subscriptions/' + $subid + '/resourceGroups/' + $imageResourceGroup
}

New-AzRoleAssignment @parameters

# Create an Azure Image gallery for storing and distributing images

$location = "West Europe"
$resourceGroupName = "SRS-AVD-IMG-RG"
$imageName = "SRS-AVD-IMG-Win11-23H2"
$galleryName = "SRSAVDGallery"
$imageDefinitionName = "SRS-AVD-IMG-Def"
$imageVersionName = "1.0.0"


# Get the image
$image = Get-AzImage -ImageName $imageName -ResourceGroupName $resourceGroupName

# Get the image definition

$imageDefinition = Get-AzGalleryImageDefinition -GalleryName $galleryName -ResourceGroupName $resourceGroupName -Name $imageDefinitionName

# Create the image version
New-AzGalleryImageVersion `
  -GalleryImageDefinitionName $imageDefinition.Name `
  -GalleryImageVersionName $imageVersionName `
  -GalleryName $galleryName `
  -ResourceGroupName $resourceGroupName `
  -Location $location `
  -Source $image.Id
