@echo off
setlocal
cd /d "%~dp0.."
if not exist "lobby\ops.env.bat" (
  echo Missing lobby\ops.env.bat
  echo Copy lobby\ops.env.example.bat to lobby\ops.env.bat and fill OPS_TOKEN / META_DATABASE_URL.
  pause
  exit /b 1
)
cd /d "%~dp0..\lobby"
call ops.env.bat
if "%OPS_TOKEN%"=="" (
  echo OPS_TOKEN is empty in lobby\ops.env.bat
  pause
  exit /b 1
)
if "%OPS_TOKEN%"=="change-me" (
  echo OPS_TOKEN is still the example value. Edit lobby\ops.env.bat
  pause
  exit /b 1
)
echo Starting lobby in %CD%
echo Public host=%LOBBY_PUBLIC_HOST%
call npm start
echo Lobby exited.
pause
