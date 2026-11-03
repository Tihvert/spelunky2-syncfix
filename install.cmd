@echo off
rem Runs syncfix.ps1 (next to this file) once to install the Spelunky 2 sync fix.
rem Pass -Uninstall or -Check to undo or just look, e.g.  install.cmd -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0syncfix.ps1" %*
echo.
pause
