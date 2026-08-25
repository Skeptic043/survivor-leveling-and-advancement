$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $PSScriptRoot '.build'
$jar = 'C:\Steam Games\steamapps\common\ProjectZomboid\projectzomboid.jar'
$java = 'C:\Steam Games\steamapps\common\ProjectZomboid\jre64\bin\java.exe'
if (Test-Path $build) { Remove-Item -Recurse -Force -LiteralPath $build }
New-Item -ItemType Directory -Path $build | Out-Null
$source = Join-Path $root 'Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\State\StateCodec.lua'
$spec = Join-Path $PSScriptRoot 'state\StateCodecSpec.lua'
$guard = Get-Content -Raw -LiteralPath $source
if ($guard -match '(?i)\b(Events|ModData|sendClientCommand|sendServerCommand|IsoPlayer|Diagnostics)\b') { throw 'Static guard failed: prohibited game or diagnostic API in StateCodec.' }
& javac -d $build (Join-Path $PSScriptRoot 'support\KahluaRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Kahlua test runner compilation failed.' }
$gameRoot = Split-Path -Parent $jar
Push-Location $gameRoot
try {
    & $java -cp "$build;$jar" KahluaRunner $source $spec
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0) { throw 'Kahlua test suite failed.' }
