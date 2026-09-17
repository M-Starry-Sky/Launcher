# 构建 Minecraft 26.x「星穹优化」并复制到启动器 assets
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
  foreach ($c in @(
      'E:\JAVA\jdk-25',
      'E:\JAVA\jdk24',
      'E:\JAVA\jdk-21.0.10'
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

& "$root\gradlew.bat" build --no-daemon
if ($LASTEXITCODE -ne 0) { throw "gradle build failed: $LASTEXITCODE" }

$libs = Join-Path $root 'build\libs'
$jar = Get-ChildItem $libs -Filter 'xingqiong-perf*.jar' |
  Where-Object { $_.Name -notmatch 'sources|dev|javadoc' } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $jar) { throw 'build/libs 中未找到 xingqiong-perf jar' }

$destDir = [System.IO.Path]::GetFullPath((Join-Path $root '..\..\assets\mods'))
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir 'xingqiong-perf-26.jar'
Copy-Item -LiteralPath $jar.FullName -Destination $dest -Force
Write-Host "OK -> $dest"
