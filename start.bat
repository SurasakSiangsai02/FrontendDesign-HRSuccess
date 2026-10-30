@echo off
rem ATTG HRSuccess [HRS] - starts API (3001) + web (5173). Close this window to stop.
cd /d "%~dp0"
title ATTG HRSuccess
if not exist api\node_modules call npm.cmd install --prefix api
start "" /min cmd /c "timeout /t 3 >nul & start http://localhost:5173"
node dev.js
pause
