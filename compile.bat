@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo   AutoHotkey v2 - Ahk2Exe Compiler Helper
echo ========================================================
echo.

set SCRIPT_NAME=cheat_assistant.ahk
set OUTPUT_NAME=cheat_assistant.exe

:: Check if script exists
if not exist "%~dp0%SCRIPT_NAME%" (
    echo [ERROR] %SCRIPT_NAME% tidak ditemukan di folder ini!
    pause
    exit /b 1
)

:: Search for Ahk2Exe.exe in common locations
set COMPILER_PATH=

if exist "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set "COMPILER_PATH=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
) else if exist "%LOCALAPPDATA%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set "COMPILER_PATH=%LOCALAPPDATA%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
) else if exist "C:\Program Files (x86)\AutoHotkey\Compiler\Ahk2Exe.exe" (
    set "COMPILER_PATH=C:\Program Files (x86)\AutoHotkey\Compiler\Ahk2Exe.exe"
)

:: Check if Ahk2Exe is found
if not defined COMPILER_PATH (
    where Ahk2Exe.exe >nul 2>&1
    if !errorlevel! equ 0 (
        set COMPILER_PATH=Ahk2Exe.exe
    )
)

if not defined COMPILER_PATH (
    echo [INFO] Compiler Ahk2Exe belum terpasang.
    echo Menyiapkan download otomatis Ahk2Exe via AutoHotkey...
    echo.
    if exist "C:\Program Files\AutoHotkey\UX\install-ahk2exe.ahk" (
        start "" "C:\Program Files\AutoHotkey\UX\AutoHotkeyUX.exe" "C:\Program Files\AutoHotkey\UX\install-ahk2exe.ahk"
        echo Jendela instalasi Ahk2Exe telah dibuka.
        echo Silakan klik 'OK' / 'Yes' pada jendela konfirmasi yang muncul di layar.
        echo Setelah terpasang, jalankan kembali compile.bat ini.
    ) else (
        echo Silakan buka 'AutoHotkey Dash' dari Start Menu, lalu pilih menu 'Compile'.
    )
    echo.
    pause
    exit /b 0
)

echo Ditemukan compiler: "%COMPILER_PATH%"
echo Mengompilasi %SCRIPT_NAME% -> %OUTPUT_NAME% ...
echo.

"%COMPILER_PATH%" /in "%~dp0%SCRIPT_NAME%" /out "%~dp0%OUTPUT_NAME%" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

if !errorlevel! equ 0 (
    echo ========================================================
    echo   [SUKSES] File executable berhasil dibuat!
    echo   Lokasi: %~dp0%OUTPUT_NAME%
    echo ========================================================
) else (
    echo [ERROR] Terjadi kesalahan saat proses kompilasi.
)

echo.
pause

