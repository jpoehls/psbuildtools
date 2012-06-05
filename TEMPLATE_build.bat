@echo off

set task=default
if (%1) neq () set task=%1

%~d0%~p0build\psake.cmd %~d0%~p0build.ps1 %task%

:: Exit and pass along the exit code from the script we just ran.
exit /B %errorlevel%