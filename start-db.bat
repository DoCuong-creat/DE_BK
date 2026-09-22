@echo off
setlocal enabledelayedexpansion
title Khoi dong PostgreSQL - DE_BK Module 1
cd /d "%~dp0"

echo ==========================================================
echo   KHOI DONG DATABASE - AI-Native DE Module 1
echo ==========================================================
echo.

echo [1/3] Kiem tra Docker Engine...
docker info >nul 2>&1
if not errorlevel 1 (
    echo       Docker Engine dang chay: OK
    goto ready
)

echo       Docker chua chay. Dang mo Docker Desktop...
if exist "C:\Program Files\Docker\Docker\Docker Desktop.exe" (
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
) else (
    echo.
    echo       LOI: Khong tim thay Docker Desktop.exe
    echo       Mo Docker Desktop thu cong roi chay lai file nay.
    goto fail
)

set /a waited=0
:waitloop
timeout /t 5 /nobreak >nul
set /a waited+=5
docker info >nul 2>&1
if not errorlevel 1 goto ready
echo       ... dang doi Docker Engine (!waited! giay)
if !waited! GEQ 180 (
    echo.
    echo       LOI: Docker Engine khong len sau 180 giay.
    goto fail
)
goto waitloop

:ready
echo.
echo [2/3] Khoi dong container postgres...
docker compose up -d postgres
if errorlevel 1 (
    echo.
    echo       LOI: docker compose that bai.
    echo       Kiem tra cong 5432 co bi PostgreSQL native chiem khong:
    echo           Get-NetTCPConnection -LocalPort 5432 -State Listen
    goto fail
)

echo.
echo [3/3] Trang thai container:
echo.
docker compose ps
echo.
echo ==========================================================
echo   SAN SANG. Thong so ket noi DBeaver:
echo     Host     : localhost
echo     Port     : 5432
echo     Database : ecommerce
echo     User     : de_user
echo     Password : de_password
echo ==========================================================
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
