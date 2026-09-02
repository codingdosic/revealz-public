# Installs Godot Android Gradle build template and enables HTTP lobby on Android.
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "android\build"
$TemplateZip = Join-Path $env:APPDATA "Godot\export_templates\4.5.1.stable\android_source.zip"
$ManifestPatch = Join-Path $ProjectRoot "platform\android\AndroidManifest.xml"

if (-not (Test-Path $TemplateZip)) {
    Write-Error "Missing Godot Android template: $TemplateZip"
}

if (-not (Test-Path $ManifestPatch)) {
    Write-Error "Missing manifest patch: $ManifestPatch"
}

Write-Host "Installing Android build template to $BuildDir ..."
if (Test-Path (Join-Path $ProjectRoot "android")) {
    Remove-Item -Recurse -Force (Join-Path $ProjectRoot "android")
}
New-Item -ItemType Directory -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "android\plugins") | Out-Null
Expand-Archive -LiteralPath $TemplateZip -DestinationPath $BuildDir -Force
Copy-Item -LiteralPath $ManifestPatch -Destination (Join-Path $BuildDir "AndroidManifest.xml") -Force
Set-Content -Path (Join-Path $ProjectRoot "android\.build_version") -Value "4.5.1.stable" -NoNewline
Write-Host "Done. Gradle build template ready with cleartext HTTP enabled."
