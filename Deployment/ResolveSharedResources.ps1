param(
    [string]$BUILD_ENV)

# This is the rg where the VNETs should be deployed
$groups = az group list --tag stack-environment=$BUILD_ENV | ConvertFrom-Json
$networkingResourceGroup = ($groups | Where-Object { $_.tags.'stack-name' -eq 'platform' -and $_.tags.'stack-environment' -eq $BUILD_ENV -and $_.tags.'stack-sub-name' -eq 'networking' }).name
Write-Host "::set-output name=resourceGroup::$networkingResourceGroup"