@echo off
rem Debug launcher - same as XmasSnow.bat but keeps a console window open so errors are visible
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0snow.ps1"
