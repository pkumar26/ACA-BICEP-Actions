// ============================================================================
// ACA Infrastructure — Multi-Environment Orchestrator
// ============================================================================
// Wires 5 Bicep modules in dependency order:
//   1. identity.bicep          — conditional UAMI creation
//   2. acr-role-assignment.bicep — AcrPull on ACR (cross-RG capable)
//   3. log-analytics.bicep     — Log Analytics workspace
//   4. managed-environment.bicep — ACA environment (conditional + VNET)
//   5. container-app.bicep     — Container app with secrets, scaling, ingress
//
// See: specs/001-aca-multienv-framework/data-model.md §3
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

@description('Full ARM resource ID of the existing Azure Container Registry. Supports cross-resource-group ACR.')
param acrResourceId string

// --- ACA Environment ---

@description('Optional: Resource ID of an existing ACA managed environment. Empty = create new.')
param existingManagedEnvironmentId string = ''

@description('Optional: Subnet resource ID for VNET integration. Empty = no VNET.')
param subnetId string = ''

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
param ingressExternal bool = false

// --- Environment Variables ---

@description('Non-sensitive environment variables for the container.')
param appEnvVars array = []

@description('Secret environment variables sourced from Key Vault.')
param secretEnvVars array = []

// --- Tags ---

@description('Tags to apply to all resources.')
param tags object = {}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var resourceSuffix = '${appName}-${environmentName}'

// Derive ACR name and resource group from the full resource ID
var acrResourceGroup = split(acrResourceId, '/')[4]
var acrName = last(split(acrResourceId, '/'))
var acrLoginServer = '${acrName}.azurecr.io'

// Conditional: create a new ACA environment or use existing
var createNewEnvironment = empty(existingManagedEnvironmentId)

// ---------------------------------------------------------------------------
// 1. User-Assigned Managed Identity (conditional)
// ---------------------------------------------------------------------------

module identity './modules/identity.bicep' = {
  name: 'identity-${resourceSuffix}'
  params: {
    resourceSuffix: resourceSuffix
    location: location
    tags: tags
    createNewIdentity: createNewIdentity
    existingIdentityResourceId: existingIdentityResourceId
  }
}

// ---------------------------------------------------------------------------
// 2. ACRPull Role Assignment (cross-RG capable)
// ---------------------------------------------------------------------------

module acrRoleAssignment './modules/acr-role-assignment.bicep' = {
  name: 'acr-role-${resourceSuffix}'
  scope: resourceGroup(acrResourceGroup)
  params: {
    acrName: acrName
    principalId: identity.outputs.identityPrincipalId
  }
}

// ---------------------------------------------------------------------------
// 3. Log Analytics Workspace (always runs)
// ---------------------------------------------------------------------------

module logAnalytics './modules/log-analytics.bicep' = {
  name: 'law-${resourceSuffix}'
  params: {
    resourceSuffix: resourceSuffix
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 4. Container Apps Managed Environment (conditional)
// ---------------------------------------------------------------------------

module managedEnv './modules/managed-environment.bicep' = if (createNewEnvironment) {
  name: 'cae-${resourceSuffix}'
  params: {
    resourceSuffix: resourceSuffix
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsPrimarySharedKey: logAnalytics.outputs.primarySharedKey
    subnetId: subnetId
  }
}

// Resolve environment ID: new module output or existing external ID
var resolvedEnvironmentId = createNewEnvironment
  ? managedEnv.outputs.environmentId
  : existingManagedEnvironmentId

// Resolve environment name for output
var resolvedEnvironmentName = createNewEnvironment
  ? managedEnv.outputs.environmentName
  : last(split(existingManagedEnvironmentId, '/'))

// ---------------------------------------------------------------------------
// 5. Container App
// ---------------------------------------------------------------------------

module containerApp './modules/container-app.bicep' = {
  name: 'ca-${resourceSuffix}'
  params: {
    resourceSuffix: resourceSuffix
    appName: appName
    location: location
    tags: tags
    managedEnvironmentId: resolvedEnvironmentId
    identityResourceId: identity.outputs.identityResourceId
    acrLoginServer: acrLoginServer
    containerImage: containerImage
    targetPort: targetPort
    containerCpu: containerCpu
    containerMemory: containerMemory
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    ingressExternal: ingressExternal
    appEnvVars: appEnvVars
    secretEnvVars: secretEnvVars
  }
  dependsOn: [
    acrRoleAssignment
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('The name of the Container App.')
output containerAppName string = containerApp.outputs.containerAppName

@description('The FQDN of the Container App.')
output containerAppFqdn string = containerApp.outputs.containerAppFqdn

@description('The resource ID of the Container App.')
output containerAppResourceId string = containerApp.outputs.containerAppResourceId

@description('The resource ID of the managed identity used by the Container App.')
output identityResourceId string = identity.outputs.identityResourceId

@description('The name of the Container Apps Managed Environment.')
output managedEnvironmentName string = resolvedEnvironmentName
