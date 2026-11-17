@echo off
chcp 65001 >nul
title Installation des Outils C++ Visual Studio pour Flutter Windows

:: 1. Vérification des droits Administrateur et élévation automatique si nécessaire
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ======================================================================
    echo   Élévation Administrateur requise...
    echo   Une fenêtre de confirmation Windows (UAC) va s'afficher.
    echo ======================================================================
    powershell -Command "Start-Process cmd -ArgumentList '/c `\"%~f0`\"' -Verb RunAs"
    exit /b
)

cls
echo ======================================================================
echo   INSTALLATION DES OUTILS C++ VISUAL STUDIO POUR RAYCOFIELDSERVICE
echo ======================================================================
echo.
echo Composants en cours d'installation :
echo  - Développement Desktop en C++ (Workload NativeDesktop)
echo  - Compilateur MSVC C++ x64/x86
echo  - C++ CMake tools pour Windows
echo  - Windows SDK
echo.
echo Veuillez patienter pendant le téléchargement et l'installation par Microsoft...
echo (Cette opération prend généralement quelques minutes selon votre connexion).
echo.

set "SETUP_EXE=C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
set "VS_PATH=C:\Program Files\Microsoft Visual Studio\18\Community"

if not exist "%SETUP_EXE%" (
    echo [ERREUR] L'installateur Visual Studio est introuvable à :
    echo %SETUP_EXE%
    pause
    exit /b 1
)

"%SETUP_EXE%" modify --installPath "%VS_PATH%" --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart

echo.
echo ======================================================================
echo   Installation terminée ! Vérification avec flutter doctor...
echo ======================================================================
echo.

cd /d "c:\Users\popatry\app_technicien"
call flutter doctor

echo.
echo ======================================================================
echo   Prêt ! Vous pouvez maintenant lancer :
echo     flutter run -d windows
echo ======================================================================
pause
