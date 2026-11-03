@echo off
rem Christmas snow launcher - runs snow.ps1 (same folder) without a console window
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0snow.ps1"
