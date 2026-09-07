Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile("pics\Logo.bmp")
$w = [Math]::Min($bmp.Width, 900); $h = [int]($bmp.Height * ($w / $bmp.Width))
$s = New-Object System.Drawing.Bitmap($bmp, $w, $h)
$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append(([char]27) + "Pq""1;1;" + $w + ";" + $h + "#0;2;0;0;0#1;2;0;47;83")
for ($y = 0; $y -lt $h; $y += 6) {
    $r = ""
    for ($x = 0; $x -lt $w; $x++) {
        $v = 0
        for ($dy = 0; $dy -lt 6; $dy++) {
            if (($y + $dy) -lt $h) {
                $p = $s.GetPixel($x, $y + $dy)
                if ($p.B -gt 100 -and $p.B -gt ($p.R * 1.3)) { $v = $v -bor (1 -shl $dy) }
            }
        }
        if ($v -gt 0) { $r += "#1" + [char](63 + $v) } else { $r += "?" }
    }
    [void]$sb.Append($r + "-`$")
}
[void]$sb.Append(([char]27) + "\")
[System.IO.File]::WriteAllText("$PWD\logo.six", $sb.ToString())

$scriptPath = ".\Software_and_Driver_Updater.cmd"
$sixelPath  = ".\logo.six"

# Read both files cleanly as arrays of lines
$scriptLines = [System.IO.File]::ReadAllLines((Resolve-Path $scriptPath))
$sixelLines  = [System.IO.File]::ReadAllLines((Resolve-Path $sixelPath))

# Find marker indices
$beginIndex = [array]::IndexOf($scriptLines, '[LOGO_DATA_BEGIN]')
$endIndex   = [array]::IndexOf($scriptLines, '[LOGO_DATA_END]')

if ($beginIndex -ge 0 -and $endIndex -gt $beginIndex) {
    # Reassemble: head + marker + sixel payload + tail
    $output = @()
    $output += $scriptLines[0..$beginIndex]
    $output += $sixelLines
    $output += $scriptLines[$endIndex..($scriptLines.Length - 1)]

    # Overwrite the script file with clean UTF-8
    [System.IO.File]::WriteAllLines((Resolve-Path $scriptPath), $output, [System.Text.Encoding]::UTF8)
    Write-Host "Successfully spliced logo.six into $scriptPath!" -ForegroundColor Green
} else {
    Write-Host "Error: Could not locate markers in $scriptPath" -ForegroundColor Red
}
