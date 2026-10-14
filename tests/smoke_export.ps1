param([string]$Executable = '')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ($Executable -eq '') { $Executable = Join-Path $projectRoot '.godot/jam-preview/WeavingRain.exe' }
$Executable = (Resolve-Path -LiteralPath $Executable).Path
$cases = @(
    @{ Mode = 'lesson'; Map = 'standard'; Targets = 1; Tropical = 'false' },
    @{ Mode = 'standard'; Map = 'standard'; Targets = 2; Tropical = 'false' },
    @{ Mode = 'far'; Map = 'far'; Targets = 2; Tropical = 'false' },
    @{ Mode = 'close'; Map = 'close'; Targets = 2; Tropical = 'false' },
    @{ Mode = 'ridges'; Map = 'ridges'; Targets = 2; Tropical = 'false' },
    @{ Mode = 'meadow'; Map = 'meadow'; Targets = 3; Tropical = 'false' },
    @{ Mode = 'valleys'; Map = 'valleys'; Targets = 3; Tropical = 'false' },
    @{ Mode = 'needs_lab'; Map = 'needs_lab'; Targets = 2; Tropical = 'false' },
    @{ Mode = 'reservoir_lab'; Map = 'reservoir_lab'; Targets = 2; Tropical = 'false' },
    @{ Mode = 'storm_coast'; Map = 'storm_coast'; Targets = 2; Tropical = 'true' }
)
foreach ($case in $cases) {
    $log = Join-Path $projectRoot ('.godot/ui-standalone-' + $case.Mode + '.log')
    $capture = Join-Path $projectRoot ('.godot/ui-standalone-' + $case.Mode + '.png')
    $arguments = @('--resolution', '1280x720', '--quit-after', '420', '--log-file', ('"' + $log + '"'), '--', '--fresh-guide', ('--capture="' + $capture + '"'))
    if ($case.Mode -ne 'lesson') { $arguments += '--layout=' + $case.Mode }
    # No --path: load only the exported, embedded resources.
    $process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    $output = Get-Content -LiteralPath $log -Raw
    $expected = 'result=0 layout=' + $case.Map + ' targets=' + $case.Targets + ' tropical=' + $case.Tropical
    if ($process.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR|ERROR:)' -or -not $output.Contains($expected) -or -not (Test-Path -LiteralPath $capture)) {
        throw ('Exported startup failed: ' + $case.Mode + '. See ' + $log)
    }
    Write-Output ('Standalone startup/render OK: ' + $case.Mode)
}
Write-Output 'EXPORTED STARTUP: 10 maps/modes verified. Startup screenshots are not gameplay completion evidence.'
