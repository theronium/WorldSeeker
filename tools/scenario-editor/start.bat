@echo off
rem Starts the scenario editor and opens it in the default browser (see README.md).
rem This file is ASCII only on purpose: cmd.exe misreads UTF-8 Japanese text in .bat files.
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
    echo Node.js was not found. Please install it from https://nodejs.org/
    pause
    exit /b 1
)
node server.js --open
pause
