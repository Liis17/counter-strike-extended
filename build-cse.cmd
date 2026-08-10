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

echo === [1/8] Build engine (waf) ===
pushd "%ENGINE_SRC%" || goto :fail
call .\waf.bat build || (popd & goto :fail)
call .\waf.bat install --destdir="%ENGINE_INSTALL%" || (popd & goto :fail)
popd

echo === [2/8] Build client (cmake) ===
pushd "%CLIENT_SRC%" || goto :fail
if not exist "build\CMakeCache.txt" (
    cmake --preset %PRESET% || (popd & goto :fail)
)
cmake --build build --config %CLIENT_CONFIG% || (popd & goto :fail)
cmake --install build --config %CLIENT_CONFIG% --prefix "%CLIENT_INSTALL%" || (popd & goto :fail)
popd

echo === [3/8] Deploy to runtime ===
if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%"

rem Engine: build/engine -> runtime/   (incl. .pdb)
robocopy "%ENGINE_INSTALL%" "%RUNTIME_DIR%" /E /NFL /NDL /NP /NJH /NJS >nul
if errorlevel 8 goto :fail

rem Client: build/cs16-client/cstrike -> runtime/cstrike/   (skip .lib)
robocopy "%CLIENT_INSTALL%\cstrike" "%RUNTIME_DIR%\cstrike" /E /NFL /NDL /NP /NJH /NJS /XF *.lib >nul
if errorlevel 8 goto :fail

echo === [4/8] Install localization ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_localization.ps1" || goto :fail

echo === [5/8] Install YaPB map configs ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_yapb_map_configs.ps1" || goto :fail

echo === [6/8] Install HUD layout ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_hud_layout.ps1" || goto :fail

echo === [7/8] Install progression config ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_progression.ps1" || goto :fail

echo === [8/8] Generate skin models ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\install_skins.ps1" || goto :fail

echo.
echo Build complete. Artifacts deployed to runtime\.
exit /b 0

:fail
echo.
echo Build FAILED.
exit /b 1
