@echo off
title WSB Flash Clean - Build Helper
echo ============================================
echo   WSB FLASH CLEAN - BUILD HELPER
echo ============================================
echo.

echo Escolha a versao que deseja compilar:
echo [1] SAFE PUBLIC PROTECTED
echo [2] AGGRESSIVE PUBLIC PROTECTED
echo.
set /p CHOICE=Opcao: 

if "%CHOICE%"=="1" (
    set SCRIPT=WSBFlashClean v3.1(SAFE).ps1
    set OUTPUT=WSBFlashClean(SAFE).exe
    goto build
)

if "%CHOICE%"=="2" (
    set SCRIPT=WSBFlashClean v3.1.ps1
    set OUTPUT=WSBFlashClean.exe
    goto build
)

echo Opcao invalida.
pause
exit /b

:build
set ICON=wsb_flash_clean.ico

echo.
echo Compilando "%SCRIPT%" ...
powershell -ExecutionPolicy Bypass -Command "Invoke-ps2exe '%SCRIPT%' '%OUTPUT%' -iconFile '%ICON%' -noConsole"

echo.
echo Build finalizado: %OUTPUT%
pause
