param primary_location string = 'centralus'
param dr_location string = 'eastus2'
param environment string
param prefix string
param branch string
param sourceIp string
param version string
param lastUpdated string = utcNow('u')
param subTagStackName string

var priNetworkPrefix = toLower('${prefix}-${primary_location}')
var drNetworkPrefix = toLower('${prefix}-${dr_location}')

var tags = {
  'stack-name': prefix
  'stack-version': version
  'stack-environment': toLower(replace(environment, '_', ''))
  'stack-branch': branch
  'stack-last-updated': lastUpdated
  'stack-sub-name': subTagStackName
}

var subnets = [
  'default'
  'ase'
  'aks'
  'aci'
  'appsvccs'
  'appsvcaltid'
  'appsvcpartapi'
  'appsvcbackend'
  'appgw'
  // Typically, we are using /24 to define subnet size. However, note that Azure Container Apps 
  // subnets are special because they require a larger subnet size so if we are adding a new subnet, 
  // it should be added on top of this comment as we are using the index of array as the subnet like 
  // 10.0.0.0/24 would be for default, 10.0.1.0/24 would be for ase etc.
  'containerappcontrol'
  'containerapp'
]

resource primary_vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${priNetworkPrefix}-pri-vnet'
  tags: tags
  location: primary_location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [for (subnetName, i) in subnets: {
      name: subnetName
      properties: {
        addressPrefix: (subnetName == 'containerappcontrol') ? '10.0.96.0/21' : (subnetName == 'containerapp') ? '10.0.104.0/21' : '10.0.${i}.0/24'
      }
    }]
  }
}

resource dr_vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${drNetworkPrefix}-dr-vnet'
  tags: tags
  location: dr_location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '172.0.0.0/16'
      ]
    }
    subnets: [for (subnetName, i) in subnets: {
      name: subnetName
      properties: {
        addressPrefix: (subnetName == 'containerappcontrol') ? '172.0.96.0/21' : (subnetName == 'containerapp') ? '172.0.104.0/21' : '172.0.${i}.0/24'
      }
    }]
  }
}

resource primary_peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-05-01' = {
  name: '${priNetworkPrefix}-pri-to-dr-peer'
  parent: primary_vnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: dr_vnet.id
    }
  }
}

resource dr_peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-05-01' = {
  name: '${drNetworkPrefix}-dr-to-pri-peer'
  parent: dr_vnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: primary_vnet.id
    }
  }
}

var allowHttp = {
  name: 'AllowHttp'
  properties: {
    description: 'Allow HTTP'
    priority: 100
    protocol: 'Tcp'
    direction: 'Inbound'
    access: 'Allow'
    sourceAddressPrefix: sourceIp
    sourcePortRange: '*'
    destinationPortRange: '80'
    destinationAddressPrefix: '*'
  }
}

var allowHttps = {
  name: 'AllowHttps'
  properties: {
    description: 'Allow HTTPS'
    priority: 110
    protocol: 'Tcp'
    direction: 'Inbound'
    access: 'Allow'
    sourceAddressPrefix: sourceIp
    sourcePortRange: '*'
    destinationPortRange: '443'
    destinationAddressPrefix: '*'
  }
}

var allowFrontdoorOnHttp = {
  name: 'AllowFrontdoorHttp'
  properties: {
    description: 'Allow Frontdoor on HTTPS'
    priority: 120
    protocol: 'Tcp'
    direction: 'Inbound'
    access: 'Allow'
    sourceAddressPrefix: 'AzureFrontDoor.Backend'
    sourcePortRange: '*'
    destinationPortRange: '80'
    destinationAddressPrefix: '*'
  }
}

var allowFrontdoorOnHttps = {
  name: 'AllowFrontdoorHttps'
  properties: {
    description: 'Allow Frontdoor on HTTPS'
    priority: 130
    protocol: 'Tcp'
    direction: 'Inbound'
    access: 'Allow'
    sourceAddressPrefix: 'AzureFrontDoor.Backend'
    sourcePortRange: '*'
    destinationPortRange: '443'
    destinationAddressPrefix: '*'
  }
}

// See: https://docs.microsoft.com/en-us/azure/application-gateway/configuration-infrastructure#network-security-groups
var allowAppGatewayV2 = {
  name: 'AllowApplicationGatewayV2Traffic'
  properties: {
    description: 'Allow Application Gateway V2 traffic'
    priority: 140
    protocol: 'Tcp'
    direction: 'Inbound'
    access: 'Allow'
    sourceAddressPrefix: 'GatewayManager'
    sourcePortRange: '*'
    destinationPortRange: '65200-65535'
    destinationAddressPrefix: '*'
  }
}

resource prinsgs 'Microsoft.Network/networkSecurityGroups@2021-05-01' = [for subnetName in subnets: {
  name: '${priNetworkPrefix}-pri-${subnetName}-subnet-nsg'
  location: primary_location
  tags: tags
  properties: {
    securityRules: (subnetName == 'aks' || startsWith(subnetName, 'containerapp')) ? [
      allowHttp
      allowHttps
      allowFrontdoorOnHttp
      allowFrontdoorOnHttps
    ] : (subnetName == 'appgw') ? [
      allowHttp
      allowHttps
      allowAppGatewayV2
    ] : []
  }
}]

// Note that all changes related to the subnet must be done on this level rathter than
// on the Virtual network resource declaration above because otherwise, the changes
// may be overwritten on this level.

@batchSize(1)
resource associateprinsg 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' = [for (subnetName, i) in subnets: {
  name: '${primary_vnet.name}/${subnetName}'
  properties: {
    addressPrefix: primary_vnet.properties.subnets[i].properties.addressPrefix
    networkSecurityGroup: {
      id: prinsgs[i].id
    }
    serviceEndpoints: (startsWith(subnetName, 'appsvc') || subnetName == 'aks') ? [
      {
        service: 'Microsoft.Sql'
        locations: [
          primary_location
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          primary_location
        ]
      }
      {
        service: 'Microsoft.ServiceBus'
        locations: [
          primary_location
        ]
      }
      {
        service: 'Microsoft.KeyVault'
        locations: [
          primary_location
        ]
      }
    ] : (subnetName == 'appgw') ? [
      {
        service: 'Microsoft.Web'
        locations: [
          primary_location
        ]
      }
    ] : []
    delegations: (subnetName == 'ase') ? [
      {
        name: 'webapp'
        properties: {
          serviceName: 'Microsoft.Web/hostingEnvironments'
        }
      }
    ] : []
  }
}]

resource drnsgs 'Microsoft.Network/networkSecurityGroups@2021-05-01' = [for subnetName in subnets: {
  name: '${drNetworkPrefix}-dr-${subnetName}-subnet-nsg'
  location: dr_location
  tags: tags
  properties: {
    securityRules: (subnetName == 'aks' || startsWith(subnetName, 'containerapp')) ? [
      allowHttp
      allowHttps
      allowFrontdoorOnHttp
      allowFrontdoorOnHttps
    ] : (subnetName == 'appgw') ? [
      allowHttp
      allowHttps
      allowAppGatewayV2
    ] : []
  }
}]

@batchSize(1)
resource associatedrnsg 'Microsoft.Network/virtualNetworks/subnets@2021-05-01' = [for (subnetName, i) in subnets: {
  name: '${dr_vnet.name}/${subnetName}'
  properties: {
    addressPrefix: dr_vnet.properties.subnets[i].properties.addressPrefix
    networkSecurityGroup: {
      id: drnsgs[i].id
    }
    serviceEndpoints: (startsWith(subnetName, 'appsvc') || subnetName == 'aks') ? [
      {
        service: 'Microsoft.Sql'
        locations: [
          dr_location
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          dr_location
        ]
      }
      {
        service: 'Microsoft.ServiceBus'
        locations: [
          dr_location
        ]
      }
      {
        service: 'Microsoft.KeyVault'
        locations: [
          dr_location
        ]
      }
    ] : (subnetName == 'appgw') ? [
      {
        service: 'Microsoft.Web'
        locations: [
          dr_location
        ]
      }
    ] : []
    delegations: (subnetName == 'ase') ? [
      {
        name: 'webapp'
        properties: {
          serviceName: 'Microsoft.Web/hostingEnvironments'
        }
      }
    ] : []
  }
}]

var aksIPTags = {
  'stack-name': 'aks-public-ip'
  'stack-version': version
  'stack-environment': toLower(replace(environment, '_', ''))
  'stack-branch': branch
  'stack-last-updated': lastUpdated
  'stack-sub-name': subTagStackName
}

resource aksStaticIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = if (environment == 'prod') {
  name: '${prefix}-aks-pip'
  tags: aksIPTags
  location: primary_location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}
