@description('The name of the Virtual Machine.')
param vmName string = 'esv' 

@description('Username for the Virtual Machine.')
param adminUsername string = 'azureuser'

@description('Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'sshPublicKey'

@description('SSH Key or password for the Virtual Machine. SSH key is recommended.')
@secure()
param adminPasswordOrKey string = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCvKcwKLiV1FdCU5XJiWA+nuaBes/hvklOHZ+J2N+YEouX+wbsTcl8Yd/ugbOiPYrc6Llrk13o/xyH1r76AVfI3Kh6esGKhBNgSyWVjq1v72jTOGPSkUitx7NFAQQYOKCzWfEtMNFlhd6nIkH9jyhQT6a/hVazD3obyCAdFpSATVOqUozMSCySSJjHxJxu48dc+uZ+Ls2w0NMJSKGShjlabW6Wlil7Q7RfEixzkzA9dRA4TEnkS4ZrL+NTU9NWogGmIb4kYz32gSr5GyfXRH69/uShfOJOXIm9ci5/5NJ7HJPrPH9aQq+AqAl6lqYkt2NqCrzezruNm4qXWnL+tbHQtnEnWkgVTUBTN4/5Mo9js8ZJ7kPBrE4yw/NY6PER/fdteFFZZDuMB6AEt+ZY4vvBwMjMbPR9nYPjKQJccG2lLiIOz5kMy8fgiU2NdpepfHsPxrUF7MHG4E0uUWrBMJMIFEoKCHttYnmKzm/xdtvUgFn0AZ2ckPUlOrxbeJWGQ1ZU='

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
  { publisher: 'redhat', offer: 'rhel',          sku: '8',               version: 'latest' }
  { publisher: 'redhat', offer: 'rhel',          sku: '8',               version: '8.0.2019050711' }
  { publisher: 'redhat', offer: 'rhel',          sku: '8',               version: 'latest' }
  { publisher: 'redhat', offer: 'rhel',          sku: '9-lvm',           version: 'latest' }
  { publisher: 'redhat', offer: 'rhel-cvm',      sku: '9_3_cvm_sev_snp', version: 'latest' }
  { publisher: 'redhat', offer: 'rhel-ha',       sku: '8.0',             version: '8.0.2020021914' }
  { publisher: 'redhat', offer: 'rhel-ha',       sku: '8_8',             version: '8.8.2023121916' }
  { publisher: 'redhat', offer: 'rhel-ha',       sku: '9_0',             version: 'latest' }
  { publisher: 'redhat', offer: 'rhel-raw',      sku: '9-raw',           version: 'latest' }
  { publisher: 'redhat', offer: 'rhel-raw',      sku: '8-raw',           version: '8.0.2021011801' }
  { publisher: 'redhat', offer: 'rhel-sap-apps', sku: '81sapapps-gen2',  version: '8.1.2021012202' }
  { publisher: 'redhat', offer: 'rhel-sap-ha',   sku: '8.1',             version: '8.1.2020060412' }
  { publisher: 'redhat', offer: 'rhel',          sku: '7-raw',           version: 'latest' }
  { publisher: 'redhat', offer: 'rhel-sap-ha',   sku: '7_9',             version: '7.9.2023100311' }
  { publisher: 'redhat', offer: 'rhel-sap-ha',   sku: '79sapha-gen2',    version: '7.9.2023100311' }
  { publisher: 'canonical', offer: '0001-com-ubuntu-server-jammy',   sku: '22_04-lts-gen2',    version: 'latest' }
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
      commandToExecute: 'rm -f /etc/cron.daily/rh*; exit 0'
    }
  }
}]

output adminUsername string = adminUsername
