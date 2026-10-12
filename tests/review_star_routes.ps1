param([string]$Label = 'star-final', [switch]$ExportReview)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$cases = @('meadow-abc', 'meadow-cab', 'valleys-mountain', 'valleys-relay', 'valleys-late')
$reports = @()
foreach ($case in $cases) {
    $path = Join-Path $projectRoot ('.godot/' + $Label + '-' + $case + '.json')
    $row = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($row.outcome -ne 'success' -or [Math]::Abs($row.water_error) -gt 0.01) { throw "Invalid route result: $case" }
    if ($row.actions.Count -ne $row.strokes) { throw "Stroke record mismatch: $case" }
    $prior = -1.0
    foreach ($action in $row.actions) {
        if ($action.time - $prior -lt 0.499 -and $prior -ge 0.0) { throw "More than one local stroke per half second: $case" }
        $prior = $action.time
    }
    if ($case -eq 'valleys-late') {
        if ($row.stars -lt 1 -or -not ($row.destroyed -contains $true) -or $row.late_clear_seconds -ne 5) { throw 'Late clearing did not exercise partial loss.' }
    } else {
        $margin = if ($row.layout -eq 'meadow') { 0.8 } else { 0.9 }
        if ($row.stars -ne 3 -or $row.destroyed -contains $true -or $row.elapsed -gt $row.limit * $margin) { throw "Three stars or time margin failed: $case" }
    }
    $row | Add-Member -NotePropertyName case -NotePropertyValue $case
    $reports += $row
}
$mountain = $reports | Where-Object case -eq 'valleys-mountain'
$relay = $reports | Where-Object case -eq 'valleys-relay'
if ($relay.per_target[2].transport -ge $mountain.per_target[2].transport -or $relay.strokes -gt $mountain.strokes -or $relay.front_strokes -le 0) {
    throw 'Cold-front route has not demonstrated fewer delivery strokes to the same C field without increasing total strokes.'
}
$reports | Select-Object case, stars, elapsed, strokes, transport_strokes, transport_distance, water_error | Format-Table -AutoSize
if ($ExportReview) {
    $summary = @($reports | Select-Object case, layout, route, order, stars, elapsed, limit, strokes, transport_strokes, transport_distance, front_strokes, per_target, water, destroyed, water_error, cold_lift, late_clear_seconds)
    $record = [ordered]@{
        description = 'Normal humidity opening; local strokes only, one per 0.5 seconds. Transport is the summed brush path for mountain feed, cloud delivery and transfer; it is not measured cloud travel. Automated evidence is not player difficulty acceptance.'
        routes = $summary
    }
    $target = Join-Path $projectRoot 'docs/star-route-review.json'
    [System.IO.File]::WriteAllText($target, ($record | ConvertTo-Json -Depth 12) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}
Write-Output 'All five route results and cold-front benefit checks passed.'
