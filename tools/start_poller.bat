@echo off
setlocal
cd /d "%~dp0.."
echo Polling lobby health. Close this window to stop.
where py >nul 2>&1
if %ERRORLEVEL%==0 (
  py -3 tools\ops_health_poll.py
) else (
  python tools\ops_health_poll.py
)
echo Poller exited.
pause
