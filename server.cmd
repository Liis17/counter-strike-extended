@echo off
setlocal enableextensions

rem ============================================================
rem  CS Dedicated Server Launcher (Xash3D FWGS + YaPB bots)
rem  Repo: counter-strike-extended
rem  Usage: server.cmd [map]      (e.g. server.cmd de_inferno)
rem ============================================================

rem --- Server parameters (edit here) ---
set "SERVER_GAME=cstrike"
set "SERVER_DLL=dlls\yapb.dll"
set "SERVER_IP=0.0.0.0"
set "SERVER_PORT=27015"
set "SERVER_MAXPLAYERS=12"
set "SERVER_MAP=de_dust2"
set "SERVER_LOG=engine.log"
set "SERVER_DEV=0"

rem --- Bot parameters (YaPB) ---
set "BOT_QUOTA=9"
set "BOT_QUOTA_MODE=normal"
set "BOT_DIFFICULTY=0"
set "BOT_LANGUAGE=ru"

rem --- Allow map override from command-line arg ---
if not "%~1"=="" set "SERVER_MAP=%~1"

rem --- Resolve runtime directory relative to this script ---
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "RUNTIME_DIR=%ROOT%\runtime"
set "XASH_EXE=%RUNTIME_DIR%\xash3d.exe"
set "GAME_DLL=%RUNTIME_DIR%\%SERVER_GAME%\%SERVER_DLL%"

rem --- Sanity checks ---
if not exist "%XASH_EXE%" (
    echo [ERROR] xash3d.exe not found at: %XASH_EXE%
    echo         Run build-cse.cmd first or check runtime\ setup.
    exit /b 1
)
if not exist "%GAME_DLL%" (
    echo [ERROR] %SERVER_DLL% not found at: %GAME_DLL%
    echo         Build cs16-client with BUILD_SERVER=ON and deploy to runtime\.
    exit /b 1
)

echo Starting dedicated server:
echo   Game:        %SERVER_GAME%
echo   DLL:         %SERVER_DLL%
echo   Bind:        %SERVER_IP%:%SERVER_PORT%
echo   Maxplayers:  %SERVER_MAXPLAYERS%
echo   Map:         %SERVER_MAP%
echo   Bots:        quota=%BOT_QUOTA% mode=%BOT_QUOTA_MODE% difficulty=%BOT_DIFFICULTY% lang=%BOT_LANGUAGE%
echo.
echo Connect from client:  connect ^<this-machine-LAN-IP^>:%SERVER_PORT%
echo.

rem --- Launch dedicated server ---
pushd "%RUNTIME_DIR%" || goto :fail
xash3d.exe -dedicated -console -dev %SERVER_DEV% ^
    -game %SERVER_GAME% ^
    -dll %SERVER_DLL% ^
    -ip %SERVER_IP% -port %SERVER_PORT% ^
    -log %SERVER_LOG% ^
    +maxplayers %SERVER_MAXPLAYERS% ^
    +sv_lan 1 ^
    +map %SERVER_MAP% ^
    +yb_quota %BOT_QUOTA% ^
    +yb_quota_mode %BOT_QUOTA_MODE% ^
    +yb_difficulty %BOT_DIFFICULTY% ^
    +yb_language %BOT_LANGUAGE%
set "EXITCODE=%ERRORLEVEL%"
popd
exit /b %EXITCODE%

:fail
echo.
echo Server launch FAILED.
exit /b 1
