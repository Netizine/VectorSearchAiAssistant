@description('Specifies the name of the Azure Machine Learning workspace.')
param workspaceName string = 'ml-${uniqueString(resourceGroup().id)}'

@description('Specifies the location for all resources.')
param location string = resourceGroup().location

@description('The name for the storage account to created and associated with the workspace.')
param storageAccountName string = 'sa${uniqueString(resourceGroup().id)}'

@description('The name for the key vault to created and associated with the workspace.')
param keyVaultName string = 'kv-${uniqueString(resourceGroup().id)}'

@description('The name for the application insights to created and associated with the workspace.')
param applicationInsightsName string = 'ai-${uniqueString(resourceGroup().id)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    supportsHttpsTrafficOnly: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableSoftDelete: false
    accessPolicies: []
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource workspace 'Microsoft.MachineLearningServices/workspaces@2020-08-01' = {
  name: workspaceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: workspaceName
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
  }
}

output workspaceName string = workspaceName
output storageAccountName string = storageAccountName
output keyVaultName string = keyVaultName
output applicationInsightsName string = applicationInsightsName
output location string = location



param serviceName string
param location string
param sku string
param hostingMode string

resource service 'Microsoft.Search/searchServices@2021-04-01-Preview' = {
  name: serviceName
  location: location
  sku: {
    name: sku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: hostingMode
  }
  tags: {}
  dependsOn: []
}

