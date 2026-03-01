using './main.bicep'

// =============================================================================
// QA Environment Parameters
// =============================================================================

param environmentName = 'qa'
param appName = 'aca-demo'
param location = 'westus2'

// --- Identity: create a new one for QA ---
param createNewIdentity = true
// param existingIdentityResourceId = ''

// --- ACR (full ARM resource ID — supports cross-resource-group ACR) ---
param acrResourceId = '/subscriptions/<sub-id>/resourceGroups/<acr-rg>/providers/Microsoft.ContainerRegistry/registries/demoacr'

// --- ACA Environment (leave empty to create new; set to existing ID to reuse) ---
param existingManagedEnvironmentId = ''

// --- VNET (leave empty for no VNET integration) ---
param subnetId = ''

// --- Container App ---
param containerImage = 'mcr.microsoft.com/k8se/quickstart:latest' // placeholder for initial deploy
param targetPort = 80
param containerCpu = '0.5'
param containerMemory = '1Gi'
param minReplicas = 1
param maxReplicas = 3
param ingressExternal = true

// --- Environment Variables ---
param appEnvVars = [
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Staging' }
  { name: 'LOG_LEVEL', value: 'Information' }
  { name: 'FEATURE_FLAG_NEW_UI', value: 'true' }
]

param secretEnvVars = [
  {
    name: 'DB_CONNECTION'
    secretRef: 'db-connection'
    keyVaultSecretUri: 'https://kv-demo-qa.vault.azure.net/secrets/db-connection'
  }
  {
    name: 'API_KEY'
    secretRef: 'api-key'
    keyVaultSecretUri: 'https://kv-demo-qa.vault.azure.net/secrets/api-key'
  }
]

// --- Tags ---
param tags = {
  Environment: 'qa'
  Project: 'demo'
  ManagedBy: 'bicep'
}
