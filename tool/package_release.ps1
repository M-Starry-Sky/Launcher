# 构建带 Logo 的企业式安装向导 + 便携版 + Web
# 在 frontend 目录：powershell -ExecutionPolicy Bypass -File tool/package_release.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $root
Set-Location $root

$version = '0.2.6'
$env:PATH = 'E:\flutter\bin;' + $env:PATH
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'

Write-Host '== branding =='
python (Join-Path $root 'tool\fix_branding_assets.py')

Write-Host '== flutter build windows =='
flutter build windows --release

$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $releaseDir 'xingqiong_launcher.exe'))) {
  throw "未找到 Release: $releaseDir"
}

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# 便携版（显式拼路径，避免 Compress-Archive 落到 dist\.zip）
$portableName = "XingqiongLauncher-$version-windows-x64-portable"
$portableDir = Join-Path $dist $portableName
$portableZip = Join-Path $dist ("XingqiongLauncher-{0}-windows-x64-portable.zip" -f $version)
if (Test-Path $portableDir) { Remove-Item $portableDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
Copy-Item (Join-Path $releaseDir '*') $portableDir -Recurse -Force
Copy-Item (Join-Path $root 'assets\images\logo.png') (Join-Path $portableDir 'logo.png') -Force
# Bundled Java runtime dir (Temurin downloads here; optional preseed jdk-17/jdk-21)
$runtimeJava = Join-Path $portableDir 'runtimes\java'
New-Item -ItemType Directory -Force -Path $runtimeJava | Out-Null
$readme = @"
Xingqiong launcher bundled Java runtime

Layout: runtimes/java/jdk-17/ or jdk-21/ (need bin/java.exe)
If empty on first launch, Temurin is downloaded here (or C:\xingqiong\runtimes\java).
Preseed JDK for offline fast start.
"@
Set-Content -Path (Join-Path $runtimeJava 'README.txt') -Value $readme -Encoding UTF8
if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
Compress-Archive -Path (Join-Path $portableDir '*') -DestinationPath $portableZip -Force
if (-not (Test-Path $portableZip) -or ((Get-Item $portableZip).Length -lt 1MB)) {
  throw "便携版 zip 生成失败: $portableZip"
}
Write-Host "OK $portableZip"

# Inno 企业安装向导
$iscc = Join-Path $root 'tool\release_tools\InnoSetup6\ISCC.exe'
if (-not (Test-Path $iscc)) {
  $iscc = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) { throw '未找到 ISCC.exe' }
& $iscc (Join-Path $root 'installer\xingqiong_setup.iss')
$setup = Join-Path $dist "XingqiongLauncher-$version-Windows-x64-Setup.exe"
if (-not (Test-Path $setup)) { throw "未生成 $setup" }
Write-Host "OK setup(wizard+logo) -> $setup"

# Web（桌面启动器依赖 dart:ffi，Web 暂不作为正式分发）
Write-Host '== skip web (ffi / desktop-only plugins) =='
Write-Host 'Android/iOS/macOS/Linux 需对应 SDK/主机，见 docs/MULTI_PLATFORM_RELEASE.md'

Write-Host '== dist =='
Get-ChildItem $dist -File | Format-Table Name, @{N='MB';E={[math]::Round($_.Length/1MB,2)}}
Write-Host 'DONE'
