@echo off
echo ========================================
echo   WSB AutoClean - Build EXE
echo ========================================

set SCRIPT=WSBAutoClean - GE v3.3.2.ps1
set OUTPUT=WSBAutoCleanGE.exe
set ICON=wsb_auto_clean_ge_v3.3.2.ico

echo.
echo Compilando...
powershell -ExecutionPolicy Bypass -Command "Invoke-ps2exe '%SCRIPT%' '%OUTPUT%' -iconFile '%ICON%' -noConsole"

echo.
echo Build finalizado!
pause
