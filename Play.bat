@echo off
set GODOT_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe

if not exist "%GODOT_EXE%" (
    echo Godot executable not found: %GODOT_EXE%
    pause
    exit /b 1
)

start "" "%GODOT_EXE%" --path "%~dp0godot"
