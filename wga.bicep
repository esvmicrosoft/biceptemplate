@description('The name of the Virtual Machine.')
param vmName string = 'machine' 

@description('Username for the Virtual Machine.')
param adminUsername string = 'azureuser'

@description('Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'password'

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string = 'Passw0rd!234avc'

@description('Unique DNS Name for the Public IP used to access the Virtual Machine.')
param dnsLabelPrefix string = toLower('${vmName}-${uniqueString(resourceGroup().id)}')

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The size of the VM')
param vmSize string = 'Standard_D2s_v3'

@description('Name of the VNET')
param virtualNetworkName string = toLower('${resourceGroup().name}-vnet')

@description('Name of the subnet in the virtual network')
param subnetName string = 'default'

@description('Name of the Network Security Group')
param networkSecurityGroupName string = '${virtualNetworkName}-NSG-CASG'

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'Standard'

@description('RightNow')
param rightnow string = utcNow('yyMMddHHmm')


@description('Storage Account SKU')
param stSKU string = 'Standard_LRS'

// This function ensures that the name is stored in lowercase.
var storageAccountName = toLower('${uniqueString(subscription().subscriptionId)}${rightnow}')

resource st 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: stSKU
  }
  kind: 'StorageV2'
   properties: {
     accessTier: 'Hot'
   }
}

output storageAccountId string = st.id
output storageAccountName string = st.name


var machines = [
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/alma8_img'    }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/oel8_img'     }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/rhel9_img'    }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/rhel8_img'    }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/sles12_img'   }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/sles15_img'   }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/ubuntu22_img' }
  { id: '/subscriptions/e1b71933-3de1-400d-bb74-dc2f9dfeca3e/resourceGroups/wga/providers/Microsoft.Compute/images/ubuntu24_img' }
]

var publicIPAddressName = '${vmName}PublicIP'
var networkInterfaceName = '${vmName}Nic'
var osDiskType = 'Standard_LRS'
var subnetAddressPrefix = '10.0.0.0/24'
var addressPrefix = '10.0.0.0/16'
var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
  patchSettings: {
      patchMode: 'ImageDefault'
  }
}
var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: false
  }
  securityType: securityType
}

var extensionName = 'GuestAttestation'
var extensionPublisher = 'Microsoft.Azure.Security.LinuxAttestation'
var extensionVersion = '1.0'
var maaTenantName = 'GuestAttestation'
var maaEndpoint = substring('emptystring', 0, 0)

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0,length(machines)): {
  name: '${networkInterfaceName}${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress[i].id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
} ]

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'CorpNetAccess'
        properties: {
          priority: 2700
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'CorpNetPublic'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'CorpNetSAW'
        properties: {
          priority: 2701
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'CorpNetSaw'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }

    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = [for i in range(0,length(machines)): {
  name: '${publicIPAddressName}${i}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${vmName}${i}-${uniqueString(resourceGroup().id)}')
    }
    idleTimeoutInMinutes: 4
  }
} ]

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0,length(machines)): {
  name: '${vmName}${i}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: machines[i]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: st.properties.primaryEndpoints.blob
      }
    }
    osProfile: {
      computerName: '${vmName}${i}'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
  }
} ]

resource vm_custom_script 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = [ for i in range(0, length(machines)): {
  parent: vm[i]
  name: 'vm${i}_custom-script'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: 'true'
    protectedSettings: {
      commandToExecute: '/usr/bin/date'
    }
  }
}]

output adminUsername string = adminUsername
