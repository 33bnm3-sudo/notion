@echo off
title Edge Remover (Admin)
echo Requesting administrator rights...
powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0Remove-Edge.ps1\"' -Verb RunAs"
