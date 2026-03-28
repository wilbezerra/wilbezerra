@echo off
title WSB Auto Clean - GE - Build Helper
echo ============================================
echo   WSB AUTO CLEAN - GHOST EDITION - BUILD HELPER
echo ============================================
echo.

echo Escolha a versao que deseja compilar:
echo [1] SAFE PUBLIC PROTECTED
echo [2] AGGRESSIVE PUBLIC PROTECTED
echo.
set /p CHOICE=Opcao: 

if "%CHOICE%"=="1" (
    set SCRIPT=WSBAutoClean - GE v3.3.2 (SAFE).ps1
    set OUTPUT=WSBAutoCleanGE(SAFE).exe
    goto build
)

if "%CHOICE%"=="2" (
    set SCRIPT=WSBAutoClean - GE v3.3.2.ps1
    set OUTPUT=WSBAutoCleanGE.exe
    goto build
)

echo Opcao invalida.
pause
exit /b

:build
set ICON=wsb_auto_clean_ge_v3.3.2

echo.
echo Compilando "%SCRIPT%" ...
powershell -ExecutionPolicy Bypass -Command "Invoke-ps2exe '%SCRIPT%' '%OUTPUT%' -iconFile '%ICON%' -noConsole"

echo.
echo Build finalizado: %OUTPUT%
pause
