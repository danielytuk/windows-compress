### 🛡️ Safe & Smart
- **Administrator Check & Elevation**: Automatically relaunches the script with admin privileges if needed.
- **Restore Point Creation**: Creates a system restore point before any changes for easy rollback.
- **Drive Type Detection**: Detects if your system drive is SSD or HDD and confirms with you before proceeding.

### ⚡ Compression & Cleanup
- **Recommended Compression Threshold**: Suggests file size thresholds based on drive type:
  - SSD: 0.5 – 1 GB
  - HDD: 1 – 2 GB
- **Large File & Folder Compression**: Compresses files larger than the specified threshold and optionally cleans temporary folders:
  - `%LOCALAPPDATA%\Temp`
  - `C:\Windows.old`
  - `C:\Temp`
  - `C:\$Recycle.Bin`

### 🖥️ Disk & Folder Analysis
- **Folder Size Calculation**: Recursively measures folder sizes, including `C:\Windows`.
- **Drive Usage Info**: Shows free, used, and total space for system drives in human-readable GB.

### 🔍 Preview & Monitoring
- **Dry-Run Mode**: Preview which files and folders would be compressed without modifying anything.
- **Real-Time Progress & ETA**: Progress bars display percent complete, elapsed time, and estimated remaining time.

### 🚀 Performance
- **Parallel Processing** (PowerShell 7+): Compress multiple files simultaneously with thread-safe progress updates.
- **Sequential Fallback**: Fully compatible with older PowerShell versions (<7).

### 🛠️ Error Handling & Recovery
- **Error Handling**: Highlights failed files/folders in red.
- **Post-Processing Overview**: Displays disk and folder usage after compression.
- **Undo / Restore Option**: Launch system restore to revert all changes.

### 🎨 User-Friendly Interface
- Colored console output for easy readability.
- Step-by-step prompts guide the user through drive confirmation, threshold selection, dry-run, and execution.
