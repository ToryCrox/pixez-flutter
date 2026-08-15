$startTime = Get-Date
# PowerShell script for building and copying Windows application
# Usage: .\build_win.ps1

$destinationDir = "E:\Program Files\PixEz"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Script started at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Building Windows application..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Build the application
$buildResult = & fvm flutter build windows
$buildExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Flutter build command completed!" -ForegroundColor Cyan
Write-Host "Debug: Exit code = $buildExitCode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($buildExitCode -ne 0) {
    Write-Host "ERROR: Flutter build returned exit code $buildExitCode" -ForegroundColor Red
    Write-Host "Build failed. Stopping script before file copy." -ForegroundColor Red
    Write-Host ""
    exit $buildExitCode
}

Write-Host "Build step completed! Proceeding to file copy..." -ForegroundColor Green
Write-Host ""

# Wait a moment to ensure files are fully written
Write-Host "Waiting for file system to sync..." -ForegroundColor Gray
Start-Sleep -Seconds 2

# Define source and destination directories
$sourceDir = "./build/windows/x64/runner/Release"
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Preparing to copy files..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Source: $sourceDir"
Write-Host "Destination: $destinationDir"
Write-Host ""

# Check if source directory exists
if (-not (Test-Path $sourceDir)) {
    Write-Host "ERROR: Source directory does not exist: $sourceDir" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "Source directory exists: OK" -ForegroundColor Green

# Close the installed application before copying files, otherwise pixez.exe
# may keep files in the destination directory locked.
Write-Host ""
Write-Host "Checking whether PixEz is running..." -ForegroundColor Yellow
$runningProcesses = @(Get-Process -Name "pixez" -ErrorAction SilentlyContinue)
if ($runningProcesses.Count -eq 0) {
    Write-Host "PixEz is not running: OK" -ForegroundColor Green
} else {
    Write-Host "PixEz is running. Requesting it to close..." -ForegroundColor Yellow
    foreach ($process in $runningProcesses) {
        try {
            if ($process.MainWindowHandle -ne 0) {
                [void]$process.CloseMainWindow()
            }
        } catch {
            Write-Host "WARNING: Failed to request PixEz to close (PID $($process.Id)): $_" -ForegroundColor Yellow
        }
    }

    $waitUntil = (Get-Date).AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 500
        $runningProcesses = @(Get-Process -Name "pixez" -ErrorAction SilentlyContinue)
    } while ($runningProcesses.Count -gt 0 -and (Get-Date) -lt $waitUntil)

    if ($runningProcesses.Count -gt 0) {
        Write-Host "PixEz did not close in time. Stopping remaining process(es)..." -ForegroundColor Yellow
        try {
            $runningProcesses | Stop-Process -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 500
            $runningProcesses = @(Get-Process -Name "pixez" -ErrorAction SilentlyContinue)
        } catch {
            Write-Host "ERROR: Failed to stop PixEz. File copy cannot continue." -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }

    if ($runningProcesses.Count -gt 0) {
        Write-Host "ERROR: PixEz is still running. File copy cannot continue." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "PixEz closed: OK" -ForegroundColor Green
}

# Create destination directory if it doesn't exist
if (-not (Test-Path $destinationDir)) {
    Write-Host "Creating destination directory..." -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Write-Host "Destination directory created: OK" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to create destination directory!" -ForegroundColor Red
        Write-Host "This may require administrator privileges." -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
} else {
    Write-Host "Destination directory exists: OK" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Starting file copy..." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Copy files
try {
    Copy-Item -Path "$sourceDir\*" -Destination $destinationDir -Recurse -Force -ErrorAction Stop
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Copy completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Files copied from:"
    Write-Host "  $sourceDir"
    Write-Host "To:"
    Write-Host "  $destinationDir"
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "ERROR: Copy failed!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$endTime = Get-Date
$duration = $endTime - $startTime
$durationString = "{0:mm}分 {0:ss}秒" -f $duration

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Script completed at $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "Total time elapsed: $durationString" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

