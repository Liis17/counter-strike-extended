@echo off
setlocal enableextensions

rem Project root = directory of this script (without trailing backslash)
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "ENGINE_SRC=%ROOT%\src\xash3d-fwgs"
set "CLIENT_SRC=%ROOT%\src\cs16-client"
set "ENGINE_INSTALL=%ROOT%\build\engine"
set "CLIENT_INSTALL=%ROOT%\build\cs16-client"
set "RUNTIME_DIR=%ROOT%\runtime"
set "PRESET=win32-release-x86"
set "CLIENT_CONFIG=Release"
set "CSE_SERVER_BUILD=%ROOT%\build\cse-server"
set "CSE_SERVER_INSTALL=%ROOT%\build\cse-server-install"

echo === [1/14] Build engine (waf) ===
pushd "%ENGINE_SRC%" || goto :fail
call .\waf.bat build || (popd & goto :fail)
call .\waf.bat install --destdir="%ENGINE_INSTALL%" || (popd & goto :fail)
popd

echo === [2/14] Build client (cmake) ===
pushd "%CLIENT_SRC%" || goto :fail
if not exist "build\CMakeCache.txt" (
    cmake --preset %PRESET% || (popd & goto :fail)
)
cmake --build build --config %CLIENT_CONFIG% || (popd & goto :fail)
cmake --install build --config %CLIENT_CONFIG% --prefix "%CLIENT_INSTALL%" || (popd & goto :fail)
popd

echo === [3/14] Build CSE server map proxy (cmake) ===
if not exist "%CSE_SERVER_BUILD%\CMakeCache.txt" (
    cmake -S "%ROOT%\src\cse\server" -B "%CSE_SERVER_BUILD%" -G "Visual Studio 17 2022" -A Win32 -DCMAKE_INSTALL_PREFIX="%CSE_SERVER_INSTALL%" || goto :fail
) else (
    cmake -S "%ROOT%\src\cse\server" -B "%CSE_SERVER_BUILD%" -DCMAKE_BUILD_TYPE=%CLIENT_CONFIG% -DCMAKE_INSTALL_PREFIX="%CSE_SERVER_INSTALL%" || goto :fail
)
cmake --build "%CSE_SERVER_BUILD%" --config %CLIENT_CONFIG% || goto :fail
cmake --install "%CSE_SERVER_BUILD%" --config %CLIENT_CONFIG% --prefix "%CSE_SERVER_INSTALL%" || goto :fail

echo === [4/14] Deploy to runtime ===
if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%"

rem Engine: build/engine -> runtime/   (incl. .pdb)
robocopy "%ENGINE_INSTALL%" "%RUNTIME_DIR%" /E /NFL /NDL /NP /NJH /NJS >nul
if errorlevel 8 goto :fail

rem Client: build/cs16-client/cstrike -> runtime/cstrike/   (skip .lib)
robocopy "%CLIENT_INSTALL%\cstrike" "%RUNTIME_DIR%\cstrike" /E /NFL /NDL /NP /NJH /NJS /XF *.lib >nul
if errorlevel 8 goto :fail

rem CSE server proxy: build/cse-server-install/cstrike/dlls -> runtime/cstrike/dlls
robocopy "%CSE_SERVER_INSTALL%\cstrike" "%RUNTIME_DIR%\cstrike" /E /NFL /NDL /NP /NJH /NJS /XF *.lib >nul
if errorlevel 8 goto :fail

echo === [5/14] Install third-party maps ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_3rdpartymaps.ps1" || goto :fail

echo === [6/14] Install CSE cstrike assets over original files ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_cse_assets.ps1" || goto :fail

echo === [7/14] Generate map catalog ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\generate_map_catalog.ps1" || goto :fail

echo === [8/14] Install server config and map cycle ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_server_config.ps1" || goto :fail

echo === [9/14] Install localization ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_localization.ps1" || goto :fail

echo === [10/14] Install YaPB map configs ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_yapb_map_configs.ps1" || goto :fail

echo === [11/14] Install HUD layout ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_hud_layout.ps1" || goto :fail

echo === [12/14] Install progression config ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_progression.ps1" || goto :fail

echo === [13/15] Validate and install cosmetics catalog ===
py -3 "%ROOT%\tools\validate_cosmetics.py" || goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_cosmetics.ps1" || goto :fail

echo === [14/15] Install bot avatars ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_bot_avatars.ps1" || goto :fail

echo === [15/15] Generate skin models ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_skins.ps1" || goto :fail

echo.
echo Build complete. Artifacts deployed to runtime\.
exit /b 0

:fail
echo.
echo Build FAILED.
exit /b 1
