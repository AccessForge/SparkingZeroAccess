@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install-Repair.ps1"
set "install_result=%errorlevel%"
if not "%install_result%"=="0" echo Installation did not finish. The error is shown above.
pause
exit /b %install_result%
