using './main.bicep'

// =============================================================================
// DEV Environment Parameters
// =============================================================================

param environmentName = 'dev'
param appName = 'aca-demo'
param location = 'westus2'

// --- Identity: create a new one for dev ---
param createNewIdentity = true
// param existingIdentityResourceId = ''
// To reuse an existing identity, set:
//   param createNewIdentity = false
//   param existingIdentityResourceId = '/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/my-existing-identity'

// --- ACR (full ARM resource ID — supports cross-RG) ---
param acrResourceId = '/subscriptions/<sub-id>/resourceGroups/<acr-rg>/providers/Microsoft.ContainerRegistry/registries/demoacr'

// --- ACA Environment ---
param existingManagedEnvironmentId = ''   // Leave empty to create a new environment
param subnetId = ''                        // Leave empty for no VNET integration

// --- Container App ---
param containerImage = 'mcr.microsoft.com/k8se/quickstart:latest' // placeholder for initial deploy
param targetPort = 80
param containerCpu = '0.25'
param containerMemory = '0.5Gi'
param minReplicas = 0
param maxReplicas = 1
param ingressExternal = true

// --- Environment Variables ---
param appEnvVars = [
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Development' }
  { name: 'LOG_LEVEL', value: 'Debug' }
  { name: 'FEATURE_FLAG_NEW_UI', value: 'true' }
]

// --- Secrets (Key Vault references — uncomment/edit when KV secrets are ready) ---
param secretEnvVars = [
  {
    name: 'DB_CONNECTION'
    secretRef: 'db-connection'
    keyVaultSecretUri: 'https://kv-demo-dev.vault.azure.net/secrets/db-connection'
  }
  {
    name: 'API_KEY'
    secretRef: 'api-key'
    keyVaultSecretUri: 'https://kv-demo-dev.vault.azure.net/secrets/api-key'
  }
]

// --- Tags ---
param tags = {
  Environment: 'dev'
  Project: 'demo'
  ManagedBy: 'bicep'
}
