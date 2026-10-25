@echo off
rem Takedawn (USA o PAL): corre desde la carpeta del proyecto, donde esta "Burnout 3 Takedown\default.xbe".
rem El programa que sirve al disco (NTSC-U o PAL) lo elige solo: burnout3-pal-retail.exe pasa el disco USA a burnout3-ntsc-u-retail.exe.
cd /d "%~dp0"
if exist "bin\burnout3-pal-retail.exe" (
    start "" "bin\burnout3-pal-retail.exe" %*
) else (
    start "" "bin\burnout3.exe" %*
)
