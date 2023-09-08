@description('Location where all resources will be deployed. This value defaults to the **West Europe** region.')
@allowed([
  'southcentralus'
  'eastus'
  'westeurope'
])
param location string = 'westeurope'

@description('''
Unique name for the deployed services below. Min length of 3 characters and a Max length 15 characters, alphanumeric only:
- Azure Cosmos DB for NoSQL
- Azure Cosmos DB for MongoDB vCore
- Azure OpenAI
- Azure App Service
- Azure Functions

. Defaults to **netizineai**.
''')
@minLength(3)
@maxLength(15)
param name string = 'netizineai'

@description('Specifies the SKU for the Azure App Service plan. Defaults to **S1**')
@allowed([
  'B1'
  'S1'
])
param appServiceSku string = 'S1'

@description('Specifies the SKU for the Azure OpenAI resource. Defaults to **S0**')
@allowed([
  'S0'
])
param openAiSku string = 'S0'

@description('MongoDb vCore user Name. 8-32 characters. No dashes. Defaults to **sysadmin**')
@minLength(8)
@maxLength(32)
param mongoDbUserName string= 'sysadmin'

@description('MongoDb vCore password. 8-64 characters, 3 of the following: lower case, upper case, numeric, symbol.')
@minLength(8)
@maxLength(64)
@secure()
param mongoDbPassword string


@description('Git repository URL for the application source. This defaults to the [`Netizine/VectorSearchAiAssistant`](https://github.com/Netizine/VectorSearchAiAssistant) repository.')
param appGitRepository string = 'https://github.com/Netizine/VectorSearchAiAssistant.git'

@description('Git repository branch for the application source. This defaults to the [**MongovCore** branch of the `Netizine/VectorSearchAiAssistant`](https://github.com/Netizine/VectorSearchAiAssistant/tree/MongovCore) repository.')
param appGetRepositoryBranch string = 'MongovCore'

var openAiSettings = {
  name: '${name}-openai'
  sku: openAiSku
  maxConversationBytes: '2000'
  completionsModel: {
    name: 'gpt-35-turbo'
    version: '0301'
    deployment: {
      name: 'completions'
    }
  }
  embeddingsModel: {
    name: 'text-embedding-ada-002'
    version: '2'
    deployment: {
      name: 'embeddings'
    }
  }
}

var cosmosDbSettings = {
  name: '${name}-cosmos-nosql'
  databaseName: 'database'
}

var mongovCoreSettings = {
  mongoClusterName: '${name}-mongo'
  mongoClusterLogin: mongoDbUserName
  mongoClusterPassword: mongoDbPassword
}

var cosmosContainers = {
  embeddingContainer: {
    name: 'embedding'
    partitionKeyPath : '/id'
    maxThroughput: 1000
  }
  completionsContainer: {
    name: 'completions'
    partitionKeyPath: '/sessionId'
    maxThroughput: 1000
  }
  productContainer: {
    name: 'product'
    partitionKeyPath: '/categoryId'
    maxThroughput: 1000
  }
  customerContainer: {
    name: 'customer'
    partitionKeyPath: '/customerId'
    maxThroughput: 1000
  }
  leasesContainer: {
    name: 'leases'
    partitionKeyPath: '/id'
    maxThroughput: 1000
  }
}

var appServiceSettings = {
  plan: {
    name: '${name}-web-plan'
    sku: appServiceSku
  }
  web: {
    name: '${name}-web'
    git: {
      repo: appGitRepository
      branch: appGetRepositoryBranch
    }
  }
  function: {
    name: '${name}-function'
    git: {
      repo: appGitRepository
      branch: appGetRepositoryBranch
    }
  }
}

resource sleepDelay 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${name}-sleep'
  location: location
  kind: 'AzurePowerShell'  
  properties: {
    forceUpdateTag: 'utcNow()'
    azPowerShellVersion: '8.3'
    timeout: 'PT10M'    
    arguments: '-seconds 30'    
    scriptContent: '''
    param ( [string] $seconds )    
    Write-Output Sleeping for: $seconds ....
    Start-Sleep -Seconds $seconds   
    Write-Output Sleep over - resuming ....
    '''
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: cosmosDbSettings.name
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        failoverPriority: 0
        isZoneRedundant: false
        locationName: location
      }
    ]
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-08-15' = {
  parent: cosmosDbAccount
  name: cosmosDbSettings.databaseName
  properties: {
    resource: {
      id: cosmosDbSettings.databaseName
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-08-15' = [for container in items(cosmosContainers):  {
  parent: cosmosDatabase
  name: container.value.name
  properties: {
    resource: {
      id: container.value.name
      partitionKey: {
        paths: [
          container.value.partitionKeyPath
        ]
        kind: 'Hash'
        version: 2
      }
    }
    options: {
      autoscaleSettings: {
        maxThroughput: container.value.maxThroughput
      }
    }
  }
}]

resource mongoCluster 'Microsoft.DocumentDB/mongoClusters@2023-03-01-preview' = {
  name: mongovCoreSettings.mongoClusterName
  location: location
  properties: {
    administratorLogin: mongovCoreSettings.mongoClusterLogin
    administratorLoginPassword: mongovCoreSettings.mongoClusterPassword
    serverVersion: '5.0'
    nodeGroupSpecs: [
      {
        kind: 'Shard'
        sku: 'M30'
        diskSizeGB: 128
        enableHa: false
        nodeCount: 1
      }
    ]
  }
}

resource mongoFirewallRulesAllowAzure 'Microsoft.DocumentDB/mongoClusters/firewallRules@2023-03-01-preview' = {
  parent: mongoCluster
  name: 'allowAzure'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource mongoFirewallRulesAllowAll 'Microsoft.DocumentDB/mongoClusters/firewallRules@2023-03-01-preview' = {
  parent: mongoCluster
  name: 'allowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiSettings.name
  location: location
  sku: {
    name: openAiSettings.sku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiSettings.name
    publicNetworkAccess: 'Enabled'
  }
}

resource openAiEmbeddingsModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: openAiSettings.embeddingsModel.deployment.name
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiSettings.embeddingsModel.name
      version: openAiSettings.embeddingsModel.version
    }
  }
  sku: {
    name: 'Standard'
    capacity: 120
  }
  dependsOn: [
    sleepDelay
  ]
}

resource openAiCompletionsModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: openAiSettings.completionsModel.deployment.name
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiSettings.completionsModel.name
      version: openAiSettings.completionsModel.version
    }
  }
  sku: {
    name: 'Standard'
    capacity: 120
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServiceSettings.plan.name
  location: location
  sku: {
    name: appServiceSettings.plan.sku
  }
}

resource appServiceWeb 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceSettings.web.name
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: '${name}storage'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
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

resource appServiceFunction 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceSettings.function.name
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
    }
  }
  dependsOn: [
    storageAccount
  ]
}

resource appServiceWebSettings 'Microsoft.Web/sites/config@2022-03-01' = {
  parent: appServiceWeb
  name: 'appsettings'
  kind: 'string'
  properties: {
    APPINSIGHTS_INSTRUMENTATIONKEY: appServiceWebInsights.properties.InstrumentationKey
    COSMOSDB__ENDPOINT: cosmosDbAccount.properties.documentEndpoint
    COSMOSDB__KEY: cosmosDbAccount.listKeys().primaryMasterKey
    COSMOSDB__DATABASE: cosmosDatabase.name
    COSMOSDB__CONTAINERS: 'completions,product,customer'
    OPENAI__ENDPOINT: openAiAccount.properties.endpoint
    OPENAI__KEY: openAiAccount.listKeys().key1
    OPENAI__EMBEDDINGSDEPLOYMENT: openAiEmbeddingsModelDeployment.name
    OPENAI__COMPLETIONSDEPLOYMENT: openAiCompletionsModelDeployment.name
    OPENAI__MAXCONVERSATIONBYTES: openAiSettings.maxConversationBytes
    MONGODB__CONNECTION: 'mongodb+srv://${mongovCoreSettings.mongoClusterLogin}:${mongovCoreSettings.mongoClusterPassword}@${mongovCoreSettings.mongoClusterName}.mongocluster.cosmos.azure.com/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000'
    MONGODB__DATABASENAME: 'vectordb'
    MONGODB__COLLECTIONNAME: 'vectors'
    MONGODB__MAXVECTORSEARCHRESULTS: '10'
  }
}

resource appServiceFunctionSettings 'Microsoft.Web/sites/config@2022-03-01' = {
  parent: appServiceFunction
  name: 'appsettings'
  kind: 'string'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${name}storage;EndpointSuffix=core.windows.net;AccountKey=${storageAccount.listKeys().keys[0].value}'
    APPINSIGHTS_INSTRUMENTATIONKEY: appServiceFunctionsInsights.properties.ConnectionString
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
    CosmosDBConnection: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
    OPENAI__ENDPOINT: openAiAccount.properties.endpoint
    OPENAI__KEY: openAiAccount.listKeys().key1
    OPENAI__EMBEDDINGSDEPLOYMENT: openAiEmbeddingsModelDeployment.name
    OPENAI__MAXTOKENS: '8191'
    MONGODB__CONNECTION: 'mongodb+srv://${mongovCoreSettings.mongoClusterLogin}:${mongovCoreSettings.mongoClusterPassword}@${mongovCoreSettings.mongoClusterName}.mongocluster.cosmos.azure.com/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000'
    MONGODB__DATABASENAME: 'vectordb'
    MONGODB__COLLECTIONNAME: 'vectors'
  }
}

resource appServiceWebDeployment 'Microsoft.Web/sites/sourcecontrols@2021-03-01' = {
  parent: appServiceWeb
  name: 'web'
  properties: {
    repoUrl: appServiceSettings.web.git.repo
    branch: appServiceSettings.web.git.branch
    isManualIntegration: true
  }
  dependsOn: [
    appServiceWebSettings
  ]
}

resource appServiceFunctionsDeployment 'Microsoft.Web/sites/sourcecontrols@2021-03-01' = {
  parent: appServiceFunction
  name: 'web'
  properties: {
    repoUrl: appServiceSettings.web.git.repo
    branch: appServiceSettings.web.git.branch
    isManualIntegration: true
  }
  dependsOn: [
    appServiceFunctionSettings
  ]
}

resource appServiceFunctionsInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appServiceFunction.name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource appServiceWebInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appServiceWeb.name
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource appServiceMLInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${name}-ai-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: '${name}-kv'
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

resource workspace 'Microsoft.MachineLearningServices/workspaces@2020-08-01' = {
  name: '${name}-ai-workspace'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: '${name}-ai-workspace'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: appServiceMLInsights.id
  }
  dependsOn: [
    searchService
    openAiAccount
  ]
}

resource searchService 'Microsoft.Search/searchServices@2021-04-01-Preview' = {
  name: '${name}-search'
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
  }
  tags: {}
  dependsOn: []
}


