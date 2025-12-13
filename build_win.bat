@echo off

setlocal enabledelayedexpansion

echo ========================================
echo Script started at %date% %time%
echo ========================================
echo.

echo ========================================
echo Building Windows application...
echo ========================================
call flutter build windows
set build_result=!errorlevel!

REM Force output flush
echo. >nul

echo.
echo ========================================
echo Flutter build command completed!
echo Debug: Exit code = !build_result!
echo ========================================

REM Only exit if build actually failed (non-zero exit code)
REM Note: Some Flutter commands may return non-zero even on success
if !build_result! neq 0 (
    echo WARNING: Flutter build returned exit code !build_result!
    echo Continuing anyway to attempt file copy...
)

echo.
echo Build step completed! Proceeding to file copy...
echo.

REM Wait a moment to ensure files are fully written
echo Waiting for file system to sync...
ping 127.0.0.1 -n 3 >nul

REM Define source and destination directories
set "source_dir=E:\Workspace\flutter\pixez_flutter\build\windows\x64\runner\Release"
set "destination_dir=E:\Program Files\PixEz"

echo.
echo ========================================
echo Preparing to copy files...
echo ========================================
echo Source: %source_dir%
echo Destination: %destination_dir%
echo.

REM Check if source directory exists
if not exist "%source_dir%" (
    echo ERROR: Source directory does not exist: %source_dir%
    pause
    exit /b 1
)
echo Source directory exists: OK

REM Create destination directory if it doesn't exist
if not exist "%destination_dir%" (
    echo Creating destination directory...
    mkdir "%destination_dir%"
    set mkdir_result=!errorlevel!
    if !mkdir_result! neq 0 (
        echo ERROR: Failed to create destination directory!
        echo This may require administrator privileges.
        echo Debug: mkdir exit code = !mkdir_result!
        pause
        exit /b 1
    )
    echo Destination directory created: OK
) else (
    echo Destination directory exists: OK
)

echo.
echo ========================================
echo Starting file copy...
echo ========================================
xcopy "%source_dir%\*" "%destination_dir%\" /s /e /y /i /q
set copy_result=!errorlevel!
echo Debug: xcopy exit code = !copy_result!

REM xcopy returns 0 for success, 1-4 for various errors
REM 0 = success, 1 = no files found, 2 = user pressed Ctrl+C, 4 = initialization error
if !copy_result! equ 0 (
    echo Copy operation completed successfully!
) else if !copy_result! equ 1 (
    echo WARNING: No files were found to copy (exit code 1)
) else if !copy_result! equ 4 (
    echo ERROR: Initialization error during copy (exit code 4)
    pause
    exit /b !copy_result!
) else (
    echo WARNING: Copy operation returned exit code !copy_result!
)

echo.
echo ========================================
echo Copy completed successfully!
echo ========================================
echo Files copied from:
echo   %source_dir%
echo To:
echo   %destination_dir%
echo.
echo ========================================
echo Script completed at %date% %time%
echo ========================================

REM End of script
endlocal