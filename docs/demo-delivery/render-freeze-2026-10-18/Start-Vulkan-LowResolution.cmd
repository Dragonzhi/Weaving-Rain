@echo off
setlocal
if not exist "%~dp0WeavingRain.exe" (
  echo Put this file next to WeavingRain.exe before running it.
  pause
  exit /b 2
)
set "WR_DIAG_DIR=%LOCALAPPDATA%\WeavingRain\Diagnostics"
if not exist "%WR_DIAG_DIR%" mkdir "%WR_DIAG_DIR%"
if not exist "%WR_DIAG_DIR%" (
  echo Could not create the diagnostics directory.
  pause
  exit /b 3
)
set "WR_DIAG_LOG=%WR_DIAG_DIR%\vulkan-%RANDOM%-%RANDOM%.log"
echo Renderer requested: vulkan
echo Log file: %WR_DIAG_LOG%
pushd "%~dp0"
start "" /wait "%~dp0WeavingRain.exe" --rendering-driver vulkan --resolution 1100x700 --verbose --log-file "%WR_DIAG_LOG%" %*
set "WR_DIAG_EXIT=%ERRORLEVEL%"
popd
echo.
echo Exit code: %WR_DIAG_EXIT%
echo Log file: %WR_DIAG_LOG%
echo If the game froze, keep the matching log for troubleshooting.
pause
exit /b %WR_DIAG_EXIT%
