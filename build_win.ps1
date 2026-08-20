# PowerShell script for building and copying Windows application
# Usage: .\build_win.ps1

$startTime = Get-Date

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
$applicationProcessName = "pixez"
$runningProcesses = @(Get-Process -Name $applicationProcessName -ErrorAction SilentlyContinue)

if ($runningProcesses.Count -gt 0) {
    Write-Host "Running $applicationProcessName process detected. Closing it before copying..." -ForegroundColor Yellow

    foreach ($process in $runningProcesses) {
        try {
            Write-Host "Closing process $($process.Id)..." -ForegroundColor Gray

            if ($process.MainWindowHandle -ne 0) {
                [void]$process.CloseMainWindow()
            }

            # WaitForExit also correctly handles a process that has already
            # exited between Get-Process and this point.
            if (-not $process.WaitForExit(5000)) {
                Write-Host "Process did not exit gracefully. Forcing process termination..." -ForegroundColor Yellow
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $process.WaitForExit()
            }

            Write-Host "Process $($process.Id) closed: OK" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: Failed to close process $($process.Id)!" -ForegroundColor Red
            Write-Host "Please close pixez manually and try again." -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
} else {
    Write-Host "No running $applicationProcessName process detected: OK" -ForegroundColor Green
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

