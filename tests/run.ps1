param(
    [string] $ProjectZomboidPath
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $PSScriptRoot '.build'

function Resolve-ProjectZomboidInstallation {
    param([string] $ExplicitPath)

    $environmentPath = [Environment]::GetEnvironmentVariable('SURVIVOR_LEVELING_PZ_INSTALL_DIR')
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates = @($ExplicitPath)
    } elseif (-not [string]::IsNullOrWhiteSpace($environmentPath)) {
        $candidates = @($environmentPath)
    } else {
        # Keep discovery bounded and predictable; do not scan Steam libraries or the registry.
        $candidates = @(
            'C:\Steam Games\steamapps\common\ProjectZomboid',
            (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common\ProjectZomboid'),
            (Join-Path $env:ProgramFiles 'Steam\steamapps\common\ProjectZomboid')
        )
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $fullPath = [IO.Path]::GetFullPath($candidate)
        $jarPath = Join-Path $fullPath 'projectzomboid.jar'
        $javaPath = Join-Path $fullPath 'jre64\bin\java.exe'
        if ((Test-Path -LiteralPath $jarPath -PathType Leaf) -and (Test-Path -LiteralPath $javaPath -PathType Leaf)) {
            return [pscustomobject]@{ Root = $fullPath; Jar = $jarPath; Java = $javaPath }
        }
    }

    $source = if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) { '-ProjectZomboidPath' } elseif (-not [string]::IsNullOrWhiteSpace($environmentPath)) { 'SURVIVOR_LEVELING_PZ_INSTALL_DIR' } else { 'the documented default locations' }
    throw "No valid Project Zomboid installation found from $source. Supply -ProjectZomboidPath or set SURVIVOR_LEVELING_PZ_INSTALL_DIR to a folder containing projectzomboid.jar and jre64\\bin\\java.exe."
}

try {
    $installation = Resolve-ProjectZomboidInstallation $ProjectZomboidPath
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
$jar = $installation.Jar
$java = $installation.Java
if (Test-Path $build) { Remove-Item -Recurse -Force -LiteralPath $build }
New-Item -ItemType Directory -Path $build | Out-Null
foreach ($luaRoot in @((Join-Path $root 'Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\State'), (Join-Path $root 'Contents\mods\SurvivorLevelingAdvancement\42.20\media\lua\shared\SurvivorLevelingAdvancement\Core'))) {
    if (Test-Path $luaRoot) { Get-ChildItem -LiteralPath $luaRoot -Filter '*.lua' -File -Recurse | ForEach-Object { if ((Get-Content -Raw -LiteralPath $_.FullName) -match '(?i)\b(Events|ModData|sendClientCommand|sendServerCommand|IsoPlayer|Diagnostics)\b') { throw "Static guard failed: prohibited game or diagnostic API in $($_.FullName)." } } }
}
& javac -d $build (Join-Path $PSScriptRoot 'support\KahluaRunner.java')
if ($LASTEXITCODE -ne 0) { throw 'Kahlua test runner compilation failed.' }
$descriptors = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'suites') -Filter '*.ps1' -File | Sort-Object Name)
if ($descriptors.Count -eq 0) { throw 'No suite descriptors found.' }
function Resolve-RepoPath([string] $relativePath) {
    if ([IO.Path]::IsPathRooted($relativePath)) { throw "Suite paths must be repository-relative: $relativePath" }
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
    $rootPrefix = ([IO.Path]::GetFullPath($root)).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Suite path escapes repository root: $relativePath" }
    return $candidate
}
$gameRoot = Split-Path -Parent $jar
Push-Location $gameRoot
try {
    foreach ($descriptor in $descriptors) {
        $result = @(& $descriptor.FullName)
        if ($result.Count -ne 1) { throw "Suite descriptor must return exactly one object: $($descriptor.Name)" }
        $suite = $result[0]
        if ($null -eq $suite.Label -or $suite.Label -isnot [string] -or [string]::IsNullOrWhiteSpace($suite.Label) -or $null -eq $suite.Spec -or $suite.Spec -isnot [string] -or [string]::IsNullOrWhiteSpace($suite.Spec)) { throw "Invalid suite descriptor: $($descriptor.Name)" }
        $specPath = Resolve-RepoPath $suite.Spec
        if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) { throw "Suite spec not found: $($suite.Spec)" }
        $javaArgs = [Collections.Generic.List[string]]::new(); $javaArgs.Add($suite.Label); $javaArgs.Add($specPath)
        $sources = @($suite.Sources); if ($sources.Count -eq 0) { throw "Suite has no sources: $($descriptor.Name)" }
        foreach ($source in $sources) {
            if ($null -eq $source.Global -or $source.Global -isnot [string] -or [string]::IsNullOrWhiteSpace($source.Global) -or $null -eq $source.Path -or $source.Path -isnot [string] -or [string]::IsNullOrWhiteSpace($source.Path)) { throw "Invalid suite source: $($descriptor.Name)" }
            $sourcePath = Resolve-RepoPath $source.Path; if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Suite source not found: $($source.Path)" }
            $javaArgs.Add($source.Global); $javaArgs.Add($sourcePath)
        }
        & $java -cp "$build;$jar" KahluaRunner $javaArgs.ToArray()
        if ($LASTEXITCODE -ne 0) { throw "Kahlua suite failed: $($descriptor.Name)" }
    }
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0) { throw 'Kahlua test suite failed.' }
