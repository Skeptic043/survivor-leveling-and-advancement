param([string]$GameRoot, [string]$Build)
$native = [IO.File]::ReadAllText((Join-Path $GameRoot 'media/lua/client/ISUI/PlayerStats/ISPlayerStatsUI.lua'))
$start = $native.IndexOf('function ISPlayerStatsUI:onAddXP(')
$end = $native.IndexOf('function ISPlayerStatsUI:updateColumns()', [Math]::Max(0, $start))
if ($start -lt 0 -or $end -lt 0) { throw 'Native Player Stats callback boundary missing' }
$fixture = "return function(ISPlayerStatsUI, isClient, SendCommandToServer)`n" + $native.Substring($start, $end-$start) + "`nend`n"
[IO.File]::WriteAllText((Join-Path $Build 'vanilla-player-stats-add-xp.lua'), $fixture, [Text.UTF8Encoding]::new($false))
