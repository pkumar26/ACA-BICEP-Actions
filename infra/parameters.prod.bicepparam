using './main.bicep'

// =============================================================================
// PROD Environment Parameters
// =============================================================================

param environmentName = 'prod'
param appName = 'aca-demo'
param location = 'westus2'

// --- Identity: create a new one for prod ---
param createNewIdentity = true
// param existingIdentityResourceId = ''

// --- ACR ---
param acrName = 'demoacr'
// param acrResourceGroup = 'rg-demo-shared'  // uncomment if ACR is in a different RG

// --- Container App ---
param containerImage = 'mcr.microsoft.com/k8se/quickstart:latest' // placeholder for initial deploy
param targetPort = 80
param containerCpu = '1'
param containerMemory = '2Gi'
param minReplicas = 1
param maxReplicas = 10
param ingressExternal = true

// --- Environment Variables ---
param appEnvVars = [
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
  { name: 'LOG_LEVEL', value: 'Warning' }
  { name: 'FEATURE_FLAG_NEW_UI', value: 'false' }
]

param secretEnvVars = [
  {
    name: 'DB_CONNECTION'
    secretRef: 'db-connection'
    keyVaultSecretUri: 'https://kv-demo-prod.vault.azure.net/secrets/db-connection'
  }
  {
    name: 'API_KEY'
    secretRef: 'api-key'
    keyVaultSecretUri: 'https://kv-demo-prod.vault.azure.net/secrets/api-key'
  }
]

// --- Tags ---
param tags = {
  Environment: 'prod'
  Project: 'demo'
  ManagedBy: 'bicep'
}
