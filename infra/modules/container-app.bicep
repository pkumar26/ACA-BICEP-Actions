// ============================================================================
// Module: Container App
// ============================================================================
// Deploys an ACA container app with:
//   - User-assigned identity for ACR pull
//   - Key Vault–backed secrets via secretEnvVars
//   - Configurable ingress (allowInsecure: false hardcoded per FR-007)
//   - Single revision mode
//   - Configurable scaling
// See: specs/001-aca-multienv-framework/data-model.md §2.5
// ============================================================================

@description('Resource suffix for naming: {appName}-{environmentName}')
param resourceSuffix string

@description('Base application name (used as container name).')
param appName string

@description('Azure region for the container app.')
param location string

@description('Tags to apply to the container app.')
param tags object

@description('Resource ID of the ACA managed environment.')
param managedEnvironmentId string

@description('Resource ID of the user-assigned managed identity.')
param identityResourceId string

@description('ACR login server (e.g., demoacr.azurecr.io).')
param acrLoginServer string

@description('Full container image reference (e.g., demoacr.azurecr.io/myapp:latest).')
param containerImage string

@description('Target port the container listens on.')
param targetPort int

@description('CPU cores allocated to the container.')
param containerCpu string

@description('Memory allocated to the container (e.g., 1Gi).')
param containerMemory string

@description('Minimum number of replicas.')
param minReplicas int

@description('Maximum number of replicas.')
param maxReplicas int

@description('Whether the container app exposes an external HTTP endpoint.')
param ingressExternal bool

@description('Non-sensitive environment variables for the container.')
param appEnvVars array = []

@description('Secret environment variables sourced from Key Vault.')
param secretEnvVars array = []

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

// Build secrets array for the container app (Key Vault references)
var containerAppSecrets = [
  for secret in secretEnvVars: {
    name: secret.secretRef
    keyVaultUrl: secret.keyVaultSecretUri
    identity: identityResourceId
  }
]

// Build env var mappings for secrets
var secretEnvVarMappings = [
  for secret in secretEnvVars: {
    name: secret.name
    secretRef: secret.secretRef
  }
]

// Merge plain env vars + secret-referenced env vars
var containerEnvVars = concat(appEnvVars, secretEnvVarMappings)

// ---------------------------------------------------------------------------
// Resources
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
    managedEnvironmentId: managedEnvironmentId
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
          server: acrLoginServer
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
