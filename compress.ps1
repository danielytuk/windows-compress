Add-Type -AssemblyName System.Windows.Forms

function Show-ErrorAndExit($message) {
    [System.Windows.Forms.MessageBox]::Show($message, "Error", "OK", "Error")
    exit 1
}

function Get-SizeBytes {
    param([string]$Path)
    try {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
        return $size
    } catch { return $null }
}

function Get-SizeInfo {
    param([string]$Path)
    $bytes = Get-SizeBytes $Path
    if ($bytes) { "{0:N2} GB" -f ($bytes / 1GB) } else { "Unknown" }
}

function Get-DiskInfo {
    param([string]$DriveLetter)
    try {
        $vol = Get-PSDrive $DriveLetter
        $free = "{0:N2} GB" -f ($vol.Free / 1GB)
        $used = "{0:N2} GB" -f (($vol.Used) / 1GB)
        $total = "{0:N2} GB" -f (($vol.Used + $vol.Free) / 1GB)
        return "Used: $used / Free: $free / Total: $total"
    } catch { return "Unknown" }
}

function Format-Time($seconds) {
    $hours = [math]::Floor($seconds / 3600)
    $minutes = [math]::Floor(($seconds % 3600) / 60)
    $secs = [math]::Floor($seconds % 60)
    if ($hours -gt 0) { return "$hours hr $minutes min" }
    elseif ($minutes -gt 0) { return "$minutes min" }
    else { return "$secs sec" }
}

function Compress-LargeFiles {
    param(
        [string]$Path,
        [long]$MinSizeBytes,
        [switch]$DryRun,
        [int]$MaxParallel = 4
    )

    $cleanupPaths = @(
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows.old",
        "C:\Temp",
        "C:\$Recycle.Bin"
    )

    $items = @()

    # Gather large files
    $items += Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
              Where-Object { -not $_.PSIsContainer -and $_.Length -ge $MinSizeBytes }

    # Gather cleanup folders
    foreach ($folder in $cleanupPaths) {
        if (Test-Path $folder) {
            $folderSize = Get-SizeBytes $folder
            $item = [PSCustomObject]@{
                FullName = $folder
                Length   = $folderSize
                IsFolder = $true
            }
            $items += $item
        }
    }

    if (-not $items) {
        Write-Host "No files or folders found larger than $([math]::Round($MinSizeBytes / 1GB,2)) GB." -ForegroundColor Yellow
        return
    }

    # Calculate total size for progress and time estimation
    $totalSize = ($items | Measure-Object -Property Length -Sum).Sum
    Write-Host "Total size to process: $([math]::Round($totalSize / 1GB,2)) GB" -ForegroundColor Cyan

    $startTime = Get-Date
    $processedSize = 0

    if ($DryRun) {
        Write-Host "`n💡 Dry-Run Mode: No files or folders will be modified." -ForegroundColor Cyan
        foreach ($item in $items) {
            $processedSize += $item.Length
            $progress = [math]::Round(($processedSize / $totalSize) * 100, 2)
            $elapsed = (Get-Date) - $startTime
            $estimatedTotalTimeSec = ($elapsed.TotalSeconds / $processedSize) * $totalSize
            $remainingSec = [math]::Max(0, $estimatedTotalTimeSec - $elapsed.TotalSeconds)
            $timeLeft = Format-Time $remainingSec
            Write-Progress -Activity "Dry-run preview" -Status "$progress% Complete - ETA: $timeLeft" -PercentComplete $progress

            if ($item.PSObject.Properties.Match('IsFolder')) {
                Write-Host "Folder -> $($item.FullName) ($([math]::Round($item.Length / 1GB,2)) GB)" -ForegroundColor DarkGray
            } else {
                Write-Host "File -> $($item.FullName) ($([math]::Round($item.Length / 1GB,2)) GB)" -ForegroundColor DarkGray
            }
        }
        Write-Progress -Activity "Dry-run preview" -Completed
        Write-Host "`nDry-run complete. No files or folders were modified." -ForegroundColor Green
        return
    }

    # Determine PS version for parallel processing
    $psMajor = $PSVersionTable.PSVersion.Major

    if ($psMajor -ge 7) {
        # Parallel processing for PS 7+
        $processedSizeRef = [ref]0
        $lock = [ref]([System.Object]::new())

        $items | ForEach-Object -Parallel {
            param($processedSizeRef, $totalSize, $lock)
            $itemSize = $PSItem.Length
            try {
                if ($PSItem.PSObject.Properties.Match('IsFolder')) {
                    Remove-Item -Path $PSItem.FullName -Recurse -Force -ErrorAction Stop
                } else {
                    compact /c /f /q "$($PSItem.FullName)" | Out-Null
                }
            } catch { Write-Host "Failed: $($PSItem.FullName)" -ForegroundColor Red }

            # Thread-safe progress update
            [System.Threading.Monitor]::Enter($lock.Value)
            try { $processedSizeRef.Value += $itemSize } finally { [System.Threading.Monitor]::Exit($lock.Value) }

            $progress = [math]::Round(($processedSizeRef.Value / $totalSize) * 100, 2)
            $elapsed = (Get-Date) - $using:startTime
            $estimatedTotalTimeSec = ($elapsed.TotalSeconds / $processedSizeRef.Value) * $totalSize
            $remainingSec = [math]::Max(0, $estimatedTotalTimeSec - $elapsed.TotalSeconds)
            $timeLeft = Format-Time $remainingSec

            Write-Progress -Activity "Processing items" -Status "$progress% Complete - ETA: $timeLeft" -PercentComplete $progress
        } -ThrottleLimit $MaxParallel -ArgumentList $processedSizeRef, $totalSize, $lock
    } else {
        # Sequential fallback
        foreach ($item in $items) {
            try {
                if ($item.PSObject.Properties.Match('IsFolder')) {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                } else {
                    compact /c /f /q "$($item.FullName)" | Out-Null
                }
            } catch { Write-Host "Failed: $($item.FullName)" -ForegroundColor Red }

            $processedSize += $item.Length
            $progress = [math]::Round(($processedSize / $totalSize) * 100, 2)
            $elapsed = (Get-Date) - $startTime
            $estimatedTotalTimeSec = ($elapsed.TotalSeconds / $processedSize) * $totalSize
            $remainingSec = [math]::Max(0, $estimatedTotalTimeSec - $elapsed.TotalSeconds)
            $timeLeft = Format-Time $remainingSec

            Write-Progress -Activity "Processing items" -Status "$progress% Complete - ETA: $timeLeft" -PercentComplete $progress
        }
        Write-Progress -Activity "Processing items" -Completed
    }
}

# --- MAIN SCRIPT ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "=== Windows Drive Compression Helper ===" -ForegroundColor Cyan

# Step 1: Restore point
$restorePointName = "Pre-DriveCompression"
try { 
    Checkpoint-Computer -Description $restorePointName -RestorePointType "MODIFY_SETTINGS" 
    Write-Host "✅ Restore point created: $restorePointName" -ForegroundColor Green 
} catch { Show-ErrorAndExit "Could not create restore point. Error: $($_.Exception.Message)" }

# Step 2: Detect drive type
try {
    $systemDrive = ($env:SystemDrive).TrimEnd('\')
    $systemDisk = Get-Partition -DriveLetter $systemDrive[0] | Get-Disk
    if ($systemDisk.MediaType) { $driveType = $systemDisk.MediaType }
    elseif ($systemDisk.SpindleSpeed -eq 0) { $driveType = "SSD" } else { $driveType = "HDD" }
} catch { Show-ErrorAndExit "Could not detect drive type. Error: $($_.Exception.Message)" }
Write-Host "Detected system drive ($systemDrive) as: $driveType" -ForegroundColor Cyan

# Step 3: Confirm drive type
$confirmation = Read-Host "Do you confirm that your system drive is actually an $driveType? (y/n)"
if ($confirmation -ne "y") { exit }

# Step 4: Show recommended threshold
switch ($driveType) {
    "SSD" { $recommended = "0.5 - 1 GB (fast SSD, smaller files OK)" }
    "HDD" { $recommended = "1 - 2 GB (slower HDD, avoid small files)" }
    default { $recommended = "1 GB (default)" }
}
Write-Host "`n💡 Recommended minimum file size for compression based on your drive type ($driveType): $recommended" -ForegroundColor Cyan
$thresholdGB = Read-Host "Enter minimum file size in GB for compression (e.g., 0.5, 1, 2)"
try { $MinSizeBytes = [math]::Round([double]$thresholdGB * 1GB) } catch { Show-ErrorAndExit "Invalid size input." }

# Step 5: Show before info
$winSizeBytes = Get-SizeBytes 'C:\Windows'
Write-Host "`n--- Current Disk/Folder Usage ---" -ForegroundColor Cyan
Write-Host "Windows folder size: $(Get-SizeInfo 'C:\Windows')" -ForegroundColor Yellow
Write-Host "Drive space: $(Get-DiskInfo $systemDrive)" -ForegroundColor Yellow

# Step 6: Dry-run
$dryRun = Read-Host "Dry-run mode? Preview only, no changes? (y/n)"
$runCompression = ($dryRun -ne "y")

# Step 7: Compression & Cleanup
Write-Host "Processing files/folders larger than $thresholdGB GB..." -ForegroundColor Cyan
if ($runCompression) {
    $run = Read-Host "Run now? (y/n)"
    if ($run -eq "y") { Compress-LargeFiles -Path "C:\" -MinSizeBytes $MinSizeBytes } else { Write-Host "Skipped processing." -ForegroundColor Yellow }
} else { Compress-LargeFiles -Path "C:\" -MinSizeBytes $MinSizeBytes -DryRun }

# Step 8: After info
if ($runCompression) {
    Write-Host "`n--- After Processing Disk/Folder Usage ---" -ForegroundColor Cyan
    Write-Host "Windows folder size: $(Get-SizeInfo 'C:\Windows')" -ForegroundColor Yellow
    Write-Host "Drive space: $(Get-DiskInfo $systemDrive)" -ForegroundColor Yellow
}

# Step 9: Undo option
$undo = Read-Host "Restore system to pre-script state? (y/n)"
if ($undo -eq "y") { Start-Process "rstrui.exe" -Wait }

Write-Host "✅ Script finished." -ForegroundColor Green
