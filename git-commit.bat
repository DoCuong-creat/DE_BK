@echo off
setlocal
title Commit + push bai tap - DE_BK Module 1
cd /d "%~dp0"

rem ==========================================================================
rem  CACH DUNG (mo CMD tai thu muc repo, hoac double-click file nay):
rem
rem    git-commit.bat "session-03: CTE, window functions, RFM, cohort"
rem
rem  Khong truyen message thi script se hoi. Mau message theo de:
rem    session-XX: <mo ta ngan>
rem
rem  Script lam 4 buoc:
rem    1. git status        - xem file nao thay doi
rem    2. git add -A        - dua TAT CA thay doi vao commit (.gitignore van loai .env, logs...)
rem    3. git commit -m ... - tao commit
rem    4. git push          - day len https://github.com/DoCuong-creat/DE_BK (nhanh master)
rem
rem  Lenh tuong duong neu muon go tay:
rem    git status
rem    git add -A
rem    git commit -m "session-03: CTE, window functions, RFM, cohort"
rem    git push origin master
rem    git log --oneline -5
rem ==========================================================================

set "MSG=%~1"
if "%MSG%"=="" set /p "MSG=Nhap commit message (vd: session-03: mo ta ngan): "
if "%MSG%"=="" (
    echo LOI: commit message rong, huy.
    goto fail
)

echo.
echo [1/4] Cac file thay doi:
git status --short
git status --porcelain | findstr . >nul
if errorlevel 1 (
    echo       Khong co gi thay doi, khong can commit.
    goto done
)

echo.
echo Message: %MSG%
set /p "OK=Commit tat ca file tren? (y/n): "
if /i not "%OK%"=="y" (
    echo Da huy.
    goto done
)

echo.
echo [2/4] git add -A
git add -A || goto fail

echo [3/4] git commit
git commit -m "%MSG%" || goto fail

echo.
echo [4/4] git push origin master
git push origin master || goto fail

echo.
echo ==========================================================
echo   XONG. 5 commit gan nhat:
git log --oneline -5
echo ==========================================================
goto done

:fail
echo.
echo Co loi, xem thong bao phia tren.
pause
exit /b 1

:done
pause
exit /b 0
