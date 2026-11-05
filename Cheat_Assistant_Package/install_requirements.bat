@echo off
title Setup Dependensi Python - Assistant
echo =======================================================
echo Menginstall dependensi Python untuk Auto-Detect OpenCV...
echo =======================================================
echo.
python -m pip install --upgrade pip
python -m pip install opencv-python numpy pillow
echo.
echo =======================================================
echo Instalasi selesai!
echo Sekarang Anda bisa menjalankan cheat_assistant.exe
echo =======================================================
pause

