<#
 .SYNOPSIS
    Deploys a template to Azure

 .DESCRIPTION
    Deploys an Azure Resource Manager template

 .PARAMETER resourceGroup
    The resource group where the template will be deployed. Can be the name of an existing or a new resource group.

 .PARAMETER location
    The resource group location. This can be hard coded in. Please run the following command to view available locations 
        Get-AzureRmLocation | Format-Table

    OR visit this webpage
        https://azure.microsoft.com/en-au/global-infrastructure/locations/

.PARAMETER storageName
    Name of the storage account to be used.

.PARAMETER vnetName
    Name of the virtual network to be used. 

.PARAMETER subnetName
    This is the name of the subnet associated with the virtual network. 

.PARAMETER LabsNSGName
    The name of the Network Security Group rules. 

.PARAMETER domainName
    Rather self explanatory, really.. ¯\_(ツ)_/¯

#>

param( 
    [parameter(Mandatory=$true)]
    [string]$resourceGroup,

    [parameter(Mandatory=$true)]
    [String]$location,

    [parameter(Mandatory=$false)]
    [String]$storageName,

    [parameter(Mandatory=$false)]
    [String]$vnetName = $resourceGroup + "NET",
    
    [parameter(Mandatory=$false)]
    [String]$subnetName = $resourceGroup + "Subnet",
    
    [parameter(Mandatory=$false)]
    [String]$LabsNSGName = $resourceGroup + "NetSec",

    [parameter(Mandatory=$false)]
    [String]$domainName = "labs.local"
)
#******************************************************************************
#                                   Comments
# To view locations for azure 
#   Get-AzureRmLocation | Format-Table
#
# maybe run this command if you aren't allowed to run it  ¯\_(ツ)_/¯
#   Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force
#******************************************************************************

#******************************************************************************
#                                  Script body
#                               Execution begins here
#******************************************************************************
$ErrorActionPreference = "SilentlyContinue"

# Install Azure modules 

Install-Module AzureRM -Force
Install-Module Azure -Force

# Login to azure account 

Write-Host "Login to Azure Account";
Login-AzureRmAccount

# Create resource group 

Get-AzureRmResourceGroup -Name $resourceGroup -ErrorVariable notPresent -ErrorAction $ErrorActionPreference | Out-Null 

if ($notPresent)
{

    Write-Host "Resource group not found. Creating new resource group"
    New-AzureRmResourceGroup -Name $resourceGroup -Location $location

}

else 
{

    Write-Host "Resource Group already exists: '$resourceGroup'" 

}

# Check if storage exist for resource group then do logic on $storageExists

$storageExists = Get-AzureRmStorageAccount -ErrorVariable notPresent -ErrorAction $ErrorActionPreference | where { $_.ResourceGroupName -eq $resourceGroup } | Sort-Object -Descending -Property CreationTime | Out-Null

if ($notPresent)
{

    Write-Host "Creating storage account for '$resourceGroup'"
    New-AzureRmStorageAccount -ResourceGroup $resourceGroup -Name $storageName -Location $location -SkuName Standard_LRS
    $storageName = Get-AzureRmStorageAccount | Sort-Object -Descending -Property CreationTime
    Set-AzureRmCurrentStorageAccount -ResourceGroupName $resourceGroup -AccountName $storageName.StorageAccountName[0]

}

else 
{

    Get-AzureRmStorageAccount where { $_.ResourceGroupName -eq $resourceGroup } | Sort-Object -Descending -Property CreationTime
    $storageName = Read-Host "Enter new/existing storage name (MUST NOT contain any spaces or capitals): "
    
    # test if setting storage account is successfull
    Set-AzureRmCurrentStorageAccount -ResourceGroupName $resourceGroup -AccountName $storageName -ErrorVariable notSuccess -ErrorAction $ErrorActionPreference 
    
    if ($notSuccess)
    {

            New-AzureRmStorageAccount -ResourceGroupName $resourceGroup -AccountName $storageName -Location $location -Type "Standard_LRS" -ErrorVariable notSuccess -ErrorAction $ErrorActionPreference
            
            if ($notSuccess)
            {

                Throw "Could not create new storage account "

            }

            else 
            {
                Write-Host "Successfully created new storage account. Storage Name: '$storageName'"

            }   

    }
    
    else 
    {

        Write-Host "Using storage account: '$storageName'"
        Get-AzureRmContext | Out-Null

    }

}

# Create subnets and network and DNS Server

Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup -ErrorVariable notPresent -ErrorAction $ErrorActionPreference | Out-Null

if ($notPresent)
{
    
    $NetName = $resourceGroup + "NET"
    $SubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name labsSubnet -AddressPrefix 192.168.0.0/24
    $vnet = New-AzureRmVirtualNetwork -ResourceGroupName $resourceGroup -Location $location -Name $vnetName -AddressPrefix 192.168.0.0/16 -Subnet $SubnetConfig
    Write-Host "Successfully created Virtual Network: '$vnetName'"

}

else
{

    $vnet = Get-AzureRmVirtualNetwork -ResourceGroup $resourceGroup -Name $NetName 
    Write-Host "Virtual Network already exist"

}

# Check for netsecgroup 

Get-AzureRmNetworkSecurityGroup -Name $LabsNSGName -ResourceGroupName $resourceGroup -ErrorVariable notPresent -ErrorAction $ErrorActionPreference | Out-Null

if ($notPresent)
{
    # Create Security Rules to allow RDP/SSH traffic, this and that 

    Write-Host "Creating Security Rules for network: '$vnetName'"
    $LabsNSGName = $resourceGroup + "NetSec"
    $RDPSecRule = New-AzureRmNetworkSecurityRuleConfig -Name RDPRule -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow 
    $SSHSecRule = New-AzureRmNetworkSecurityRuleConfig -Name SSHRUle -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
    $SQLSecRUle = New-AzureRmNetworkSecurityRuleConfig -Name SQLRule -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 1433 -Access Allow
    $SMBSecRule = New-AzureRmNetworkSecurityRuleConfig -Name SMBRule -Protocol Tcp -Direction Inbound -Priority 1003 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 445 -Access Allow 
    $ICMPSecRule = New-AzureRmNetworkSecurityRuleConfig -Name ICMPRule -Protocol Tcp -Direction Inbound -Priority 1004 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange Any -Access Allow 
    $LabsNSG = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroup -Name $LabsNSGName -SecurityRules $RDPSecRule, $SSHSecRule, $SQLSecRule, $SMBSecRule $ICMPSecRule | Out-Null 
    Write-Host "Successfully Created '$NetName' Security Rules"

}

else {

    $LabsNSG = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroup -Name $LabsNSGName | Out-Null
    Write-Host "Network Security Group already exists: '$LabsNSGName'"
}

# Provision some VMs 

# DC 1 

Write-Host "Creating Windows AD DC Environment.."
$vmName1 = "DC1"
$NICName = $vmName1 + "NIC"
$PIPName = $vmName1 + "PIP"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 
$credsDC1 = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password
$publicIPDC = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id -PrivateIpAddress "192.168.0.250" -PublicIpAddressId $publicIPDC.Id -NetworkSecurityGroupId $NSG.Id
$DCConfig1 = New-AzureRmVMConfig -VMName $vmName1 -VMSize Standard_D1 | Set-AzureRmVMOperatingSystem -Windows -ComputerName $vmName1 -Credential $credsDC1 | Set-AzureRmVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2012-R2-Datacenter -Version latest | Add-AzureRmVMNetworkInterface -Id $NIC.id
Write-Host "Deploying Windows Server: '$vmName1'.."
New-AzureRmVm -ResourceGroupName $resourceGroup -Location $location -VM $DCConfig1
$VMNameGot = Get-AzureRmVM -Name $vmName1 -ResourceGroupName $resourceGroup 

# DC 2

Write-Host "Creating Windows AD DC Environment.."
$vmName2 = "DC2"
$NICName = $vmName2 + "NIC"
$PIPName = $vmName2 + "PIP"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 	
$credsDC2 = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password
$publicIPDC2 = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id -PrivateIpAddress "192.168.0.251" -PublicIpAddressId $publicIPDC2.Id -NetworkSecurityGroupId $NSG.Id
$DCConfig2 = New-AzureRmVMConfig -VMName $vmName2 -VMSize Standard_D1 | Set-AzureRmVMOperatingSystem -Windows -ComputerName $vmName2 -Credential $credsDC2 | Set-AzureRmVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2012-R2-Datacenter -Version latest | Add-AzureRmVMNetworkInterface -Id $NIC.Id 
Write-Host "Deploying Windows Server: '$vmName2'"
New-AzureRmVm -ResourceGroupName $resourceGroup -Location $location -VM $DCConfig2

# SQL Server

Write-Host "Creating SQL Server Environment..."
$vmName3 ="SQLServer"
$NICName = $vmName3 + "NIC"
$PIPName = $vmName3 + "PIP"
$diskName = "SQLServerTestDisk"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 
$credsSQL = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password 
$publicIP = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id PrivateIpAddress "192.168.0.252" -PublicIpAddressId $publicIP.Id -NetworkSecurityGroupId $NSG.Id 
$SQLVMConfig = New-AzureRmVMConfig -VMName $vmName3 -VMSize Standard_B1ms | Set-AzureRmVMOperatingSystem -Windows -ComputerName $vmName3 -Credential $credsSQL -ProvisionVMAgent -EnableAutoUpdate | Set-AzureRmVMSourceImage -PublisherName "MicrosoftSQLServer" -Offer "SQL2017-WS2016" -Skus "Standard" -Version "latest" | Add-AzureRmVMNetworkInterface -Id $NIC.Id  
Write-Host "Deploying SQL Server '$vmName3'"
New-AzureRmVM -ResourceGroupName $resourceGroup -Location $location -VM $SQLVMConfig

# Linux Box1

Write-Host "Creating Linux Server Environment.."
$vmName4 = "LinuxBox1"
$NICName = $vmName4 + "NIC"
$PIPName = $vmName4 + "PIP"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 
$credsLin1 = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password 
$publicIP = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id -PublicIpAddressId $publicIP.Id -NetworkSecurityGroupId $NSG.Id 
$LinuxConfig1 = New-AzureRmVMConfig -VMName $vmName4 -VMSize Standard_B1s | Set-AzureRmVMOperatingSystem -Linux -ComputerName $vmName4 -Credential $credsLin1 | Set-AzureRmVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus 14.04.2-LTS -Version latest | Add-AzureRmVMNetworkInterface -Id $NIC.Id 
Write-Host "Deploying Lunux Server: '$vmName4'"
New-AzureRmVm -ResourceGroupName $resourceGroup -Location $location -VM $LinuxConfig1

# Linux Box2

Write-Host "Creating Linux Server Environment.."
$vmName5 = "LinuxBox2"
$NICName = $vmName5 + "NIC"
$PIPName = $vmName5 + "PIP"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 
$credsLin2 = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password 
$publicIP = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id -PublicIpAddressId $publicIP.Id -NetworkSecurityGroupId $NSG.Id 
$LinuxConfig2 = New-AzureRmVMConfig -VMName $vmName5 -VMSize Standard_B1s | Set-AzureRmVMOperatingSystem -Linux -ComputerName $vmName5 -Credential $credsLin2 | Set-AzureRmVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus 14.04.2-LTS -Version latest | Add-AzureRmVMNetworkInterface -Id $NIC.Id 
Write-Host "Deploying Lunux Server: '$vmName5'"
New-AzureRmVm -ResourceGroupName $resourceGroup -Location $location -VM $LinuxConfig2



Write-Host "Creating Windows Client Environment.."
$vmName7 = "WinBox1"
$NICName = $vmName7 + "NIC"
$PIPName = $vmName7 + "PIP"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 
$credsWin1 = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password 
$publicIP = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id -PublicIpAddressId $publicIP.Id -NetworkSecurityGroupId $NSG.Id 
$WindowsConfig1 = New-AzureRmVMConfig -VMName $vmName7 -VMSize Standard_B1s | Set-AzureRmVMOperatingSystem -Windows -ComputerName $vmName7 -Credential $credsWin1 | Set-AzureRmVMSourceImage -PublisherName MicrosoftWindowsDesktop -Offer Windows-10 -Skus RS3-Pro -Version latest | Add-AzureRmVMNetworkInterface -Id $NIC.Id 
Write-Host "Deploying Windows Client: '$vmName7'"
New-AzureRmVm -ResourceGroupName $resourceGroup -Location $location -VM $WindowsConfig1 -Verbose 


Write-Host "Creating Windows Client Environment.."
$vmName8 = "WinBox2"
$NICName = $vmName8 + "NIC"
$PIPName = $vmName8 + "PIP"
$username = "labadmin"
$password = "LabPassw0rd!" | ConvertTo-SecureString -AsPlainText -Force 
$credsWin2 = New-Object -typename System.Management.Automation.PSCredential -argumentlist $username, $password 
$publicIP = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location -Name $PIPName -AllocationMethod Static -IdleTimeoutInMinutes 4
$NIC = New-AzureRmNetworkInterface -Name $NICName -ResourceGroupName $resourceGroup -Location $location -SubnetID $vnet.Subnets[0].Id -PublicIpAddressId $publicIP.Id -NetworkSecurityGroupId $NSG.Id 
$WindowsConfig2 = New-AzureRmVMConfig -VMName $vmName8 -VMSize Standard_B1s | Set-AzureRmVMOperatingSystem -Windows -ComputerName $vmName8 -Credential $credsWin2 | Set-AzureRmVMSourceImage -PublisherName MicrosoftWindowsDesktop -Offer Windows-10 -Skus RS3-Pro -Version latest | Add-AzureRmVMNetworkInterface -Id $NIC.Id 
Write-Host "Deploying Windows Client: '$vmName8'"
New-AzureRmVm -ResourceGroupName $resourceGroup -Location $location -VM $WindowsConfig2