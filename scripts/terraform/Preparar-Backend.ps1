# Genera configuracion desde outputs del bootstrap ya aplicado; no crea recursos.
[CmdletBinding()]
param(
    [ValidateSet('dev', 'preprod', 'prod')]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bootstrap = Join-Path $root 'terraform\bootstrap'
$output = & terraform "-chdir=$bootstrap" output -json
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron leer los outputs del bootstrap.' }
$outputs = ($output -join "`n") | ConvertFrom-Json
$bucket = $outputs.tfstate_bucket.value
$table = $outputs.tflock_table.value
if ($bucket -notmatch '^academia-premier-tfstate-519119252721-[a-f0-9]{8}$' -or
    $table -ne 'academia-premier-tflock-519119252721') {
    throw 'Los outputs no corresponden al bootstrap del proyecto nuevo.'
}

$destination = Join-Path $root "terraform\environments\$Environment"
foreach ($stack in @('red-y-base', 'supabase-propio')) {
    @"
bucket                 = "$bucket"
key                    = "$Environment/$stack/terraform.tfstate"
region                 = "us-east-2"
dynamodb_table         = "$table"
encrypt                = true
allowed_account_ids    = ["519119252721"]
expected_bucket_owner  = "519119252721"
"@ | Set-Content -Path (Join-Path $destination "$stack.backend.hcl") -Encoding ascii
}
@"
tfstate_bucket = "$bucket"
"@ | Set-Content -Path (Join-Path $destination 'state.auto.tfvars') -Encoding ascii
Write-Host "Configuracion preparada para $Environment en $destination"
