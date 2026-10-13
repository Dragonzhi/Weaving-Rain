param(
    [string]$GodotPath = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe',
    [string]$StartAt = ''
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
    @{ Name = 'compact-feedback'; Script = 'res://tests/test_compact_feedback.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=meadow'); Resolution = '1920x1080' },
    @{ Name = 'hud-layouts'; Script = 'res://tests/test_hud_layouts.gd'; Headless = $false; Args = @('--fresh-guide', '--free-play') },
    @{ Name = 'wind-tools'; Script = 'res://tests/test_wind_tools.gd'; Headless = $true },
    @{ Name = 'wind-tools-scene'; Script = 'res://tests/test_wind_tools_scene.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=meadow') },
    @{ Name = 'open-boundary'; Script = 'res://tests/test_open_boundary.gd'; Headless = $true },
    @{ Name = 'map-resources'; Script = 'res://tests/test_map_resources.gd'; Headless = $true },
    @{ Name = 'plot-needs'; Script = 'res://tests/test_plot_needs.gd'; Headless = $true },
    @{ Name = 'reservoir-tropical'; Script = 'res://tests/test_reservoir_tropical.gd'; Headless = $true },
    @{ Name = 'ground-rain'; Script = 'res://tests/test_ground_rain.gd'; Headless = $true },
    @{ Name = 'rain-area-scene'; Script = 'res://tests/test_rain_area_scene.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=reservoir_lab'); Resolution = '1920x1080' },
    @{ Name = 'rain-layers'; Script = 'res://tests/test_rain_layers.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=reservoir_lab'); Resolution = '1920x1080' },
    @{ Name = 'tropical-scene'; Script = 'res://tests/test_tropical_scene.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=storm_coast'); Resolution = '1920x1080' },
    @{ Name = 'plot-needs-scene'; Script = 'res://tests/test_plot_needs_scene.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=needs_lab'); Resolution = '1920x1080' },
    @{ Name = 'star-levels'; Script = 'res://tests/test_star_levels.gd'; Headless = $true },
    @{ Name = 'water-reserve'; Script = 'res://tests/test_water_reserve.gd'; Headless = $true },
    @{ Name = 'three-star-finish'; Script = 'res://tests/test_three_star_finish.gd'; Headless = $true },
    @{ Name = 'rating'; Script = 'res://tests/test_rating.gd'; Headless = $true },
    @{ Name = 'vortex-wind'; Script = 'res://tests/test_vortex_wind.gd'; Headless = $true },
    @{ Name = 'vortex-scene'; Script = 'res://tests/test_vortex_scene.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=needs_lab'); Resolution = '1920x1080' },
    @{ Name = 'vortex-gather'; Script = 'res://tests/measure_vortex_gather.gd'; Headless = $true },
    @{ Name = 'editor-map'; Editor = $true; Headless = $true; Args = @('--editor-map-check') },
    @{ Name = 'tuning'; Script = 'res://tests/test_tuning.gd'; Headless = $false; Args = @('--fresh-guide') },
    @{ Name = 'scene'; Script = 'res://tests/test_scene.gd'; Headless = $false; Args = @('--fresh-guide') },
    @{ Name = 'star-scene'; Script = 'res://tests/test_star_scene.gd'; Headless = $false; Args = @('--fresh-guide', '--free-play') },
    @{ Name = 'plot-feedback'; Script = 'res://tests/test_plot_feedback.gd'; Headless = $false; Args = @('--fresh-guide', '--free-play') },
    @{ Name = 'render-fields'; Script = 'res://tests/test_render_fields.gd'; Headless = $false; Args = @('--fresh-guide', '--free-play') },
    @{ Name = 'moisture-surface'; Script = 'res://tests/test_moisture_surface.gd'; Headless = $false },
    @{ Name = 'cloud-surface'; Script = 'res://tests/test_cloud_surface.gd'; Headless = $false; Args = @('--fresh-guide') },
    @{ Name = 'replay'; Script = 'res://tests/replay_weather.gd'; Headless = $true },
    @{ Name = 'lesson-replay'; Script = 'res://tests/replay_weather.gd'; Headless = $true; Args = @('--lesson', '--snapshot=res://.godot/lesson-snapshot.json') },
    @{ Name = 'dual-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--mountain') },
    @{ Name = 'dual-relay'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--snapshot=res://.godot/relay-snapshot.json') },
    @{ Name = 'far-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=far', '--mountain-with-cold') },
    @{ Name = 'far-relay'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=far', '--snapshot=res://.godot/far-snapshot.json') },
    @{ Name = 'close-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=close', '--mountain-with-cold', '--snapshot=res://.godot/close-snapshot.json') },
    @{ Name = 'close-reverse'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=close', '--mountain-with-cold', '--reverse') },
    @{ Name = 'ridges-mountain'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=ridges', '--mountain-with-cold', '--snapshot=res://.godot/ridges-snapshot.json') },
    @{ Name = 'meadow-level'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=meadow', '--mountain-with-cold') },
    @{ Name = 'valleys-level'; Script = 'res://tests/replay_relay.gd'; Headless = $true; Args = @('--layout=valleys', '--mountain-with-cold') },
    @{ Name = 'meadow-three-abc'; Script = 'res://tests/replay_star_levels.gd'; Headless = $true; Args = @('--layout=meadow', '--order=0,1,2', '--output=res://.godot/star-final-meadow-abc.json') },
    @{ Name = 'meadow-three-cab'; Script = 'res://tests/replay_star_levels.gd'; Headless = $true; Args = @('--layout=meadow', '--order=2,0,1', '--output=res://.godot/star-final-meadow-cab.json') },
    @{ Name = 'valleys-three-mountain'; Script = 'res://tests/replay_star_levels.gd'; Headless = $true; Args = @('--layout=valleys', '--route=mountain', '--output=res://.godot/star-final-valleys-mountain.json') },
    @{ Name = 'valleys-three-relay'; Script = 'res://tests/replay_star_levels.gd'; Headless = $true; Args = @('--layout=valleys', '--route=relay', '--output=res://.godot/star-final-valleys-relay.json') },
    @{ Name = 'valleys-late-clear'; Script = 'res://tests/replay_star_levels.gd'; Headless = $true; Args = @('--layout=valleys', '--late-clear=5', '--partial', '--output=res://.godot/star-final-valleys-late.json') },
    @{ Name = 'wind-tools-route'; Script = 'res://tests/replay_wind_tools_viewport.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=meadow'); Resolution = '1920x1080' },
    @{ Name = 'needs-ordinary-first'; Script = 'res://tests/replay_plot_needs.gd'; Headless = $true },
    @{ Name = 'needs-seedling-first'; Script = 'res://tests/replay_plot_needs.gd'; Headless = $true; Args = @('--reverse') },
    @{ Name = 'needs-partial-loss'; Script = 'res://tests/replay_plot_needs.gd'; Headless = $true; Args = @('--reverse', '--late=5') },
    @{ Name = 'needs-viewport-route'; Script = 'res://tests/replay_plot_needs_viewport.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=needs_lab'); Resolution = '1920x1080' },
    @{ Name = 'vortex-viewport-route'; Script = 'res://tests/replay_vortex_viewport.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=needs_lab'); Resolution = '1920x1080' },
    @{ Name = 'vortex-control-route'; Script = 'res://tests/replay_vortex_viewport.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=needs_lab', '--no-vortex'); Resolution = '1920x1080' },
    @{ Name = 'reservoir-route'; Script = 'res://tests/replay_reservoir_tropical.gd'; Headless = $true; Args = @('--layout=reservoir_lab') },
    @{ Name = 'tropical-pool-first'; Script = 'res://tests/replay_reservoir_tropical.gd'; Headless = $true },
    @{ Name = 'tropical-farm-first'; Script = 'res://tests/replay_reservoir_tropical.gd'; Headless = $true; Args = @('--reverse') },
    @{ Name = 'tropical-partial-loss'; Script = 'res://tests/replay_reservoir_tropical.gd'; Headless = $true; Args = @('--loss') },
    @{ Name = 'tropical-pure'; Script = 'res://tests/replay_reservoir_tropical.gd'; Headless = $true; Args = @('--pure') },
    @{ Name = 'tropical-viewport-pool'; Script = 'res://tests/replay_tropical_viewport.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=storm_coast'); Resolution = '1920x1080' },
    @{ Name = 'tropical-viewport-farm'; Script = 'res://tests/replay_tropical_viewport.gd'; Headless = $false; Args = @('--fresh-guide', '--layout=storm_coast', '--reverse'); Resolution = '1920x1080' }
)
if ($StartAt -ne '' -and $checks.Name -notcontains $StartAt) { throw "Unknown check name: $StartAt" }
$started = $StartAt -eq ''
foreach ($check in $checks) {
    if (-not $started -and $check.Name -ne $StartAt) { continue }
    $started = $true
    $logPath = Join-Path $cacheDirectory ($check.Name + '-check.log')
    $arguments = @('--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $logPath + '"'))
    if ($check.ContainsKey('Script')) { $arguments += @('--script', $check.Script) }
    if ($check.ContainsKey('Editor')) { $arguments += @('--editor', '--quit-after', '240') }
    if ($check.ContainsKey('Resolution')) { $arguments += @('--resolution', $check.Resolution) }
    if ($check.Headless) { $arguments = @('--headless') + $arguments }
    if ($check.ContainsKey('Args')) { $arguments += @('--') + $check.Args }
    $checkProcess = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $output = Get-Content -LiteralPath $logPath -Raw
    Write-Output $output.TrimEnd()
    if ($checkProcess.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR|ERROR:)') {
        throw "Check failed: $($check.Name). See $logPath"
    }
    if ($check.ContainsKey('Editor') -and $output -notmatch 'EDITOR MAP: 29 checks, 0 failures') { throw 'Editor plugin check did not finish.' }
}
& (Join-Path $PSScriptRoot 'review_star_routes.ps1')
if ($StartAt -eq '') {
    Write-Output 'All rules, map-editor, tuning, feedback, viewport, and thirty playthrough checks passed.'
} else {
    Write-Output "Checks from '$StartAt' and route review passed; earlier checks were not rerun."
}
