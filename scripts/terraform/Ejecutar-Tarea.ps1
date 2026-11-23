# Entrada comun para las tareas de VS Code. Solo validacion, pruebas y planes.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'preprod', 'prod')]
    [string]$Environment,
    [Parameter(Mandatory)]
    [ValidateSet('Validate', 'CheckFormat', 'Test', 'Plan', 'PrepareBackend')]
    [string]$Action,
    [ValidateSet('all', 'bootstrap', 'red-y-base', 'supabase-propio')]
    [string]$Stack = 'all'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$configuration = Join-Path $root "terraform\environments\$Environment"
$saved = @{}
foreach ($name in @('AWS_PROFILE', 'AWS_REGION', 'TF_WORKSPACE', 'TF_DATA_DIR', 'TF_INPUT')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Invoke-Terraform {
    param([string[]]$TerraformArgs)
    & terraform @TerraformArgs
    if ($LASTEXITCODE -ne 0) { throw "Terraform fallo (codigo $LASTEXITCODE)." }
}

try {
    $env:AWS_PROFILE = 'cloud-migracion'
    $env:AWS_REGION = 'us-east-2'
    $env:TF_WORKSPACE = 'default'
    $env:TF_INPUT = '0'
    Write-Host "Entorno: $Environment | Accion: $Action | Modulo: $Stack"

    if ($Action -eq 'CheckFormat') {
        Invoke-Terraform -TerraformArgs @("-chdir=$root", 'fmt', '-check', '-recursive', 'terraform')
        return
    }
    if ($Action -eq 'PrepareBackend') {
        $env:TF_DATA_DIR = Join-Path $root 'terraform\bootstrap\.terraform'
        & (Join-Path $PSScriptRoot 'Preparar-Backend.ps1') -Environment $Environment
        return
    }
    if ($Action -eq 'Plan' -and $Stack -eq 'all') {
        throw 'Seleccionar un modulo para plan; respetar el orden bootstrap, red y servicios.'
    }

    $stacks = if ($Stack -eq 'all') { @('bootstrap', 'red-y-base', 'supabase-propio') } else { @($Stack) }
    foreach ($module in $stacks) {
        if ($Action -eq 'Test' -and $module -eq 'bootstrap') { continue }
        $directory = Join-Path $root "terraform\$module"
        # Las comprobaciones sin backend no alteran la inicializacion de los planes.
        $mode = if ($Action -eq 'Plan') { 'runtime' } else { 'checks' }
        $env:TF_DATA_DIR = Join-Path $configuration ".terraform\$mode\$module"
        New-Item -ItemType Directory -Force -Path $env:TF_DATA_DIR | Out-Null

        if ($Action -in @('Validate', 'Test')) {
            Invoke-Terraform -TerraformArgs @("-chdir=$directory", 'init', '-backend=false', '-input=false')
            $command = if ($Action -eq 'Validate') { 'validate' } else { 'test' }
            Invoke-Terraform -TerraformArgs @("-chdir=$directory", $command, '-no-color')
            continue
        }

        if ($module -eq 'bootstrap') {
            # Bootstrap es compartido: conservar el backend local y su estado existente.
            $env:TF_DATA_DIR = Join-Path $directory '.terraform'
            Invoke-Terraform -TerraformArgs @("-chdir=$directory", 'init', '-input=false')
            Invoke-Terraform -TerraformArgs @("-chdir=$directory", 'plan', '-input=false')
            continue
        }

        $backend = Join-Path $configuration "$module.backend.hcl"
        $variables = Join-Path $configuration "$module.tfvars"
        $stateVariables = Join-Path $configuration 'state.auto.tfvars'
        foreach ($file in @($backend, $variables)) {
            if (-not (Test-Path -LiteralPath $file)) {
                throw "Falta $file. Tras aplicar bootstrap, ejecutar la tarea Preparar backend."
            }
        }
        $planArgs = @("-chdir=$directory", 'plan', '-input=false', "-var-file=$variables")
        if ($module -eq 'supabase-propio') {
            if (-not (Test-Path -LiteralPath $stateVariables)) {
                throw 'Falta state.auto.tfvars. Ejecutar Preparar backend.'
            }
            $planArgs += "-var-file=$stateVariables"
        }
        Invoke-Terraform -TerraformArgs @("-chdir=$directory", 'init', '-reconfigure', '-input=false', "-backend-config=$backend")
        Invoke-Terraform -TerraformArgs $planArgs
    }
}
finally {
    foreach ($name in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
}
