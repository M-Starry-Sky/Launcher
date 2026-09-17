# 构建「星穹优化」一体化模组并复制到启动器 assets
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

# Loom/Gradle 8.8 需要 JDK 17–21；避免系统默认更高版本导致 class file 68
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
  foreach ($c in @(
      'E:\JAVA\jdk-21.0.10',
      'E:\JAVA\jdk-21',
      'C:\Program Files\Java\jdk-21',
      'C:\Program Files\Java\jdk-17'
    )) {
    if (Test-Path "$c\bin\java.exe") {
      $env:JAVA_HOME = $c
      break
    }
  }
}
if ($env:JAVA_HOME) {
  $env:PATH = "$env:JAVA_HOME\bin;" + $env:PATH
  Write-Host "JAVA_HOME=$env:JAVA_HOME"
}

if (Test-Path "$root\gradlew.bat") {
  & "$root\gradlew.bat" build --no-daemon
} else {
  gradle build --no-daemon
}

$libs = Join-Path $root 'build\libs'
$jar = Get-ChildItem $libs -Filter 'xingqiong-perf*.jar' |
  Where-Object { $_.Name -notmatch 'sources|dev|javadoc' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $jar) { throw 'build/libs 中未找到 xingqiong-perf jar' }

$destDir = [System.IO.Path]::GetFullPath((Join-Path $root '..\..\assets\mods'))
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir 'xingqiong-perf.jar'
Copy-Item -LiteralPath $jar.FullName -Destination $dest -Force
$legacy = Join-Path $destDir 'xingqiong-hud-bridge.jar'
if ($legacy -and (Test-Path -LiteralPath $legacy)) { Remove-Item -LiteralPath $legacy -Force }
Write-Host "OK -> $dest"
