@echo off
rem Entry point to run run_on_phone.sh from PowerShell / cmd (2026-09-21).
rem run_on_phone.sh needs Git Bash. Typing "bash" in PowerShell/cmd starts WSL (Linux) bash instead, which cannot run it.
rem This file starts Git Bash explicitly and passes all arguments through.
rem Usage (from anywhere in the repo):  tools\dev\android\run_on_phone.cmd ["regex to wait for in logcat"]
setlocal
set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not exist "%GITBASH%" (
  echo Git Bash not found. Install Git for Windows, or run run_on_phone.sh from Git Bash. 1>&2
  exit /b 1
)
rem The script finds its own folder from $0, so pass it with forward slashes.
set "SCRIPT=%~dp0run_on_phone.sh"
set "SCRIPT=%SCRIPT:\=/%"
"%GITBASH%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%
