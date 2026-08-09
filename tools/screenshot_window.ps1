param(
    [string]$ProcessName = "xash3d",
    [string]$OutFile = "K:\source\counter-strike-extended\runtime\window_capture.png"
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern IntPtr SetForegroundWindow(IntPtr hWnd);
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$proc = Get-Process $ProcessName -ErrorAction Stop
$hwnd = $proc.MainWindowHandle
[Win32]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

$rect = New-Object Win32+RECT
[Win32]::GetWindowRect($hwnd, [ref]$rect) | Out-Null

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

$bmp = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()
Write-Output "Saved: $OutFile ($width x $height)"
