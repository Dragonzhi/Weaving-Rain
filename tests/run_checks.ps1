param(
    [string]$GodotPath = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$cacheDirectory = Join-Path $projectRoot '.godot'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
if (-not (Test-Path -LiteralPath $cacheDirectory)) {
    New-Item -ItemType Directory -Path $cacheDirectory | Out-Null
}
$checks = @(
    @{ Name = 'weather'; Script = 'res://tests/test_weather.gd'; Headless = $true },
    @{ Name = 'cold-weather'; Script = 'res://tests/test_cold_weather.gd'; Headless = $true },
    @{ Name = 'scene'; Script = 'res://tests/test_scene.gd'; Headless = $false },
    @{ Name = 'replay'; Script = 'res://tests/replay_weather.gd'; Headless = $true },
    @{ Name = 'dual-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--mountain') },
    @{ Name = 'dual-relay'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--snapshot=res://.godot/relay-snapshot.json') }
)
foreach ($check in $checks) {
    $logPath = Join-Path $cacheDirectory ($check.Name + '-check.log')
    $arguments = @('--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $logPath + '"'), '--script', $check.Script)
    if ($check.Headless) { $arguments = @('--headless') + $arguments }
    if ($check.ContainsKey('Args')) { $arguments += @('--') + $check.Args }
    $checkProcess = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $output = Get-Content -LiteralPath $logPath -Raw
    Write-Output $output.TrimEnd()
    if ($checkProcess.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR|ERROR:)') {
        throw "Check failed: $($check.Name). See $logPath"
    }
}
Write-Output 'All baseline, cold-weather, viewport, and both dual-route playthrough checks passed.'
