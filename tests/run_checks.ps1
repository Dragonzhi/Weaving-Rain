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
    @{ Name = 'onboarding'; Script = 'res://tests/test_onboarding.gd'; Headless = $true },
    @{ Name = 'layouts'; Script = 'res://tests/test_layouts.gd'; Headless = $true },
    @{ Name = 'wind-path'; Script = 'res://tests/test_wind_path.gd'; Headless = $true },
    @{ Name = 'scene'; Script = 'res://tests/test_scene.gd'; Headless = $false; Args = @('--fresh-guide') },
    @{ Name = 'render-fields'; Script = 'res://tests/test_render_fields.gd'; Headless = $false; Args = @('--free-play') },
    @{ Name = 'cloud-surface'; Script = 'res://tests/test_cloud_surface.gd'; Headless = $false },
    @{ Name = 'replay'; Script = 'res://tests/replay_weather.gd'; Headless = $true },
    @{ Name = 'lesson-replay'; Script = 'res://tests/replay_weather.gd'; Headless = $true; Args = @('--lesson', '--snapshot=res://.godot/lesson-snapshot.json') },
    @{ Name = 'dual-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--mountain') },
    @{ Name = 'dual-relay'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--snapshot=res://.godot/relay-snapshot.json') },
    @{ Name = 'far-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=far', '--mountain-with-cold') },
    @{ Name = 'far-relay'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=far', '--snapshot=res://.godot/far-snapshot.json') },
    @{ Name = 'close-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=close', '--mountain-with-cold', '--snapshot=res://.godot/close-snapshot.json') },
    @{ Name = 'close-reverse'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=close', '--mountain-with-cold', '--reverse') }
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
Write-Output 'All weather, onboarding, layout, wind-path, cloud-surface, viewport, and eight playthrough checks passed.'
