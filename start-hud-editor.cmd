@echo off
cd /d "%~dp0"
start "" http://localhost:8080/
npx --yes http-server tools/hud-editor -p 8080 -c-1
