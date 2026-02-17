// ============================================================================
// ACA Infrastructure - Multi-Environment Deployment
// ============================================================================
// Provisions: User-Assigned Identity (optional), ACRPull role, Log Analytics,
//             Managed Environment, and Container App with env vars + secrets.
// ============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Environment name (dev, qa, prod).')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Base name for the application. Used to derive resource names.')
param appName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

// --- Identity ---

@description('Set to true to create a new user-assigned managed identity; false to use an existing one.')
param createNewIdentity bool = true

@description('Resource ID of an existing user-assigned managed identity. Required when createNewIdentity is false.')
param existingIdentityResourceId string = ''

// --- ACR ---

@description('Name of the existing Azure Container Registry (without .azurecr.io).')
param acrName string

// NOTE: If the ACR is in a different resource group, extract the role
// assignment into a Bicep module deployed at that resource group scope.
// This template assumes the ACR lives in the same resource group.

// --- Container App ---

@description('Container image to deploy. Use a placeholder for initial infra provisioning.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Target port the container listens on.')
param targetPort int = 80

@description('CPU cores allocated to the container.')
param containerCpu string = '0.5'

@description('Memory allocated to the container (e.g., 1Gi).')
param containerMemory string = '1Gi'

@description('Minimum number of replicas.')
param minReplicas int = 0

@description('Maximum number of replicas.')
param maxReplicas int = 3

@description('Whether the container app exposes an external HTTP endpoint.')
param ingressExternal bool = true

// --- Environment Variables ---

@description('Non-sensitive environment variables for the container.')
param appEnvVars array = []
// Example: [ { name: 'LOG_LEVEL', value: 'Debug' } ]

@description('Secret environment variables sourced from Key Vault.')
param secretEnvVars array = []
// Example: [ { name: 'DB_CONNECTION', secretRef: 'db-connection', keyVaultSecretUri: 'https://kv.vault.azure.net/secrets/db-connection' } ]

// --- Tags ---

@description('Tags to apply to all resources.')
param tags object = {}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var resourceSuffix = '${appName}-${environmentName}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// Build secrets array for the container app (Key Vault references)
var containerAppSecrets = [
  for secret in secretEnvVars: {
    name: secret.secretRef
    keyVaultUrl: secret.keyVaultSecretUri
    identity: identityResourceId
  }
]

// Build env var mappings for secrets (extracted to avoid BCP138 in concat)
var secretEnvVarMappings = [
  for secret in secretEnvVars: {
    name: secret.name
    secretRef: secret.secretRef
  }
]

// Merge plain env vars + secret-referenced env vars
var containerEnvVars = concat(appEnvVars, secretEnvVarMappings)

// ---------------------------------------------------------------------------
// 1. User-Assigned Managed Identity (conditional)
// ---------------------------------------------------------------------------

resource newIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createNewIdentity) {
  name: 'id-${resourceSuffix}'
  location: location
  tags: tags
}

// Reference existing identity when not creating a new one
resource existingIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!createNewIdentity) {
  name: last(split(existingIdentityResourceId, '/'))!
}

// Resolved identity values used by downstream resources
var identityResourceId = createNewIdentity ? newIdentity.id : existingIdentityResourceId
var identityPrincipalId = createNewIdentity ? newIdentity.properties.principalId : existingIdentity!.properties.principalId

// ---------------------------------------------------------------------------
// 2. ACRPull Role Assignment on existing ACR
// ---------------------------------------------------------------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identityResourceId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// 3. Log Analytics Workspace
// ---------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${resourceSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ---------------------------------------------------------------------------
// 4. Container Apps Managed Environment
// ---------------------------------------------------------------------------

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${resourceSuffix}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 5. Container App
// ---------------------------------------------------------------------------

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${resourceSuffix}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: ingressExternal
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: identityResourceId
        }
      ]
      secrets: containerAppSecrets
    }
    template: {
      containers: [
        {
          name: appName
          image: containerImage
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          env: containerEnvVars
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
  dependsOn: [
    acrPullRoleAssignment
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('The name of the Container App.')
output containerAppName string = containerApp.name

@description('The FQDN of the Container App.')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn

@description('The resource ID of the Container App.')
output containerAppResourceId string = containerApp.id

@description('The resource ID of the managed identity used by the Container App.')
output identityResourceId string = identityResourceId

@description('The name of the Container Apps Managed Environment.')
output managedEnvironmentName string = managedEnv.name
