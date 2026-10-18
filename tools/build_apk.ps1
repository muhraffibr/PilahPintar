<#
  Build APK PilahPintar dengan toolchain di C:\Users\<user>\fltools.

  Contoh:
    .\tools\build_apk.ps1                 # mode simulasi, APK arm64 (±19 MB)
    .\tools\build_apk.ps1 -Firebase       # mode Firebase (butuh firebase_config.json)
    .\tools\build_apk.ps1 -Universal      # APK semua arsitektur (±53 MB)

  Hasil build:
    - Selalu disalin ke root proyek: PilahPintar-<versi>-<mode>-<abi>.apk
      (diabaikan git).
    - Build -Firebase juga disalin ke apk\PilahPintar-firebase-<abi>.apk.
      File ini ikut ter-commit; namanya tetap agar link di GitHub tidak putus.
#>
param(
  [switch]$Firebase,
  [switch]$Universal
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Tools = Join-Path $env:USERPROFILE 'fltools'
$Jdk = Get-ChildItem $Tools -Directory -Filter 'jdk-*' | Select-Object -First 1
if (-not $Jdk) { throw "JDK tidak ditemukan di $Tools" }

$env:JAVA_HOME = $Jdk.FullName
$env:ANDROID_HOME = Join-Path $Tools 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = Join-Path $Tools 'gradle'
# Path TEMP Windows berbentuk pendek (LENOVO~1) membuat Java gagal membuka
# socket lokal; arahkan TEMP Java ke folder biasa.
$Tmp = Join-Path $Tools 'tmp'
New-Item -ItemType Directory -Force $Tmp | Out-Null
$env:TEMP = $Tmp
$env:TMP = $Tmp
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$Tmp -Djava.io.tmpdir=$Tmp"
$env:Path = "$($env:JAVA_HOME)\bin;$(Join-Path $Tools 'flutter\bin');$env:Path"

$buildArgs = @('build', 'apk', '--release')
if (-not $Universal) {
  $buildArgs += @('--split-per-abi', '--target-platform', 'android-arm64')
}
$suffix = 'simulasi'
if ($Firebase) {
  $config = Join-Path $Root 'firebase_config.json'
  if (-not (Test-Path $config)) {
    throw 'firebase_config.json belum ada. Salin firebase_config.example.json lalu isi.'
  }
  $buildArgs += "--dart-define-from-file=$config"
  $suffix = 'firebase'
}

Push-Location $Root
try {
  # Java menulis info ke stderr; jangan anggap itu error PowerShell.
  $ErrorActionPreference = 'Continue'
  & flutter @buildArgs
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($exitCode -ne 0) { throw "flutter build gagal ($exitCode)" }
  $version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value
  $source = if ($Universal) { 'app-release.apk' } else { 'app-arm64-v8a-release.apk' }
  $abi = if ($Universal) { 'universal' } else { 'arm64' }
  $built = Join-Path $Root "build\app\outputs\flutter-apk\$source"
  $target = Join-Path $Root "PilahPintar-$version-$suffix-$abi.apk"
  Copy-Item $built $target -Force
  Write-Host "APK siap: $target"

  if ($Firebase) {
    $apkDir = Join-Path $Root 'apk'
    New-Item -ItemType Directory -Force $apkDir | Out-Null
    $shared = Join-Path $apkDir "PilahPintar-firebase-$abi.apk"
    Copy-Item $built $shared -Force
    $sizeMb = [math]::Round((Get-Item $shared).Length / 1MB, 1)
    Write-Host "Disalin ke: $shared (versi $version, $sizeMb MB)"
    Write-Host 'Unggah ke GitHub dengan:'
    Write-Host '  git add apk'
    Write-Host "  git commit -m `"Perbarui APK $version`""
    Write-Host '  git push'
  }
} finally {
  Pop-Location
}
