@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aidd-bootstrap-ticket.ps1" %*
