@description('The name of the Virtual Machine.')
param vmName string = 'xyz' 

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
param vmSize string = 'Standard_b4s_v2'

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


var machines = [
  { name: 'rhel97i',    imageid: {publisher: 'redhat'             , offer: 'rhel'             , sku: '97-gen2'            , version: 'latest'  }}
]

var publicIPAddressName = '${vmName}PublicIP'
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
  name: '${machines[i].name}nic'
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
        name: 'AzureCloud'
        properties: {
          priority: 2700
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureCloud'
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
  name: '${machines[i].name}pubip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('${machines[i].name}-${uniqueString(resourceGroup().id)}')
    }
    idleTimeoutInMinutes: 4
  }
} ]

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0,length(machines)): {
  name: machines[i].name
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
      imageReference: machines[i].imageid
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
      }
    }
    osProfile: {
      computerName: 'fixed'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
  }
} ]


output adminUsername string = adminUsername
