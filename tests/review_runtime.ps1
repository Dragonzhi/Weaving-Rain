param([string]$Label = 'final4')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$rows = @()
foreach ($layout in @('standard', 'far', 'close')) {
    $path = Join-Path $projectRoot ('.godot/runtime-' + $Label + '-' + $layout + '.json')
    $reports = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    if ($reports.Count -ne 6) { throw "Expected six runtime samples: $path" }
    foreach ($kind in @('cloud', 'rain', 'cold')) {
        foreach ($drag in @($false, $true)) {
            $sample = @($reports | Where-Object { $_.layout -eq $layout -and $_.kind -eq $kind -and $_.drag -eq $drag })
            if ($sample.Count -ne 1) { throw "Missing or duplicate sample: $layout / $kind / $drag" }
            $row = $sample[0]
            $suffix = if ($drag) { '-drag' } else { '-idle' }
            $csvPath = Join-Path $projectRoot ('.godot/runtime-' + $Label + '-' + $layout + '-' + $kind + $suffix + '.csv')
            $lineCount = (Get-Content -LiteralPath $csvPath | Measure-Object -Line).Lines - 1
            if ($row.frames -le 0 -or $row.frames -ne $lineCount) { throw "Frame count does not match CSV: $csvPath" }
            if ($row.p95 -le 0 -or $row.p99 -lt $row.p95) { throw "Invalid frame percentiles: $path" }
            if ($null -eq $row.simulation_seconds -or $row.simulation_seconds -lt $row.sample_seconds * 0.99 -or $row.final_backlog_ms -gt 100.0) {
                throw "Runtime sample did not maintain fixed-step simulation speed: $path / $kind / $drag"
            }
            $rows += $row
        }
    }
}
$rows | Select-Object layout, kind, drag, frames, p95, p99, slow_33ms, simulation_seconds, final_backlog_ms | Format-Table -AutoSize
$failed = @($rows | Where-Object { $_.p95 -gt 16.7 -or $_.p99 -gt 20.0 })
if ($failed.Count -gt 0) { throw "$($failed.Count) runtime samples exceed P95 16.7 ms / P99 20 ms." }
Write-Output 'All 18 runtime samples meet P95 <= 16.7 ms and P99 <= 20 ms.'
