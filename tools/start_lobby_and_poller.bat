@echo off
REM Opens lobby and poller in two windows. Does not start them in the background as services.
cd /d "%~dp0"
start "revealz-lobby" "%~dp0start_lobby.bat"
start "revealz-poller" "%~dp0start_poller.bat"
