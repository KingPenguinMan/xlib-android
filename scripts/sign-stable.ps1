param(
    [Parameter(Mandatory)][string]$Version,
    [string]$KeyDirectory = $(if ($env:ZLIB_KEY_DIR) { $env:ZLIB_KEY_DIR } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.android/z-lib-release' }),
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a numeric version, e.g. 0.1.2' }
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $env:ANDROID_HOME 'build-tools/36.0.0'
$signer = Join-Path $tools $(if ($IsWindows) { 'apksigner.bat' } else { 'apksigner' })
$aapt = Join-Path $tools $(if ($IsWindows) { 'aapt.exe' } else { 'aapt' })
$release = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $root "releases/v$Version-stable" }
New-Item -ItemType Directory -Force $release | Out-Null
foreach ($abi in 'arm64-v8a','armeabi-v7a','x86_64') {
    $inputApk = Join-Path $root "build/app/outputs/flutter-apk/app-$abi-release.apk"
    $metadata = & $aapt dump badging $inputApk
    if ($LASTEXITCODE -or $metadata[0] -notlike "*versionName='$Version'*") { throw "Version mismatch: $inputApk" }
    $outputApk = Join-Path $release "xlib-android-v$Version-$abi.apk"
    & $signer sign --out $outputApk --v4-signing-enabled false --rotation-min-sdk-version 28 --lineage "$KeyDirectory/lineage.bin" --ks "$KeyDirectory/legacy.keystore" --ks-pass pass:android --next-signer --ks "$KeyDirectory/stable.p12" --ks-pass "file:$KeyDirectory/keystore.pass" $inputApk
    if ($LASTEXITCODE) { throw "Signing failed: $abi" }
    & $signer verify $outputApk
    if ($LASTEXITCODE) { throw "Verification failed: $abi" }
}
