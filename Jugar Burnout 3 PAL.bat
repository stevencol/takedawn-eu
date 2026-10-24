@echo off
rem Takedawn (PAL): runs from the project folder, where "Burnout 3 Takedown\default.xbe" is.
cd /d "%~dp0"
start "" "bin\burnout3.exe" %*
