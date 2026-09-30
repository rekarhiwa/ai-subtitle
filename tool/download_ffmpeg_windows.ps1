# Download Windows FFmpeg (Gyan essentials) into third_party/ffmpeg/windows
$ErrorActionPreference = "Stop"
$outDir = Join-Path $PSScriptRoot "..\third_party\ffmpeg\windows"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$releaseApi = "https://api.github.com/repos/GyanD/codexffmpeg/releases/latest"
$rel = Invoke-RestMethod -Uri $releaseApi -Headers @{ "User-Agent" = "ai-subtitle-app" }
$asset = $rel.assets | Where-Object { $_.name -match "essentials.*\.zip$" } | Select-Object -First 1
if (-not $asset) { throw "No essentials FFmpeg asset found" }

$zip = Join-Path $env:TEMP "ffmpeg-win.zip"
Write-Host "Downloading $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
$extract = Join-Path $env:TEMP "ffmpeg-extract"
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $extract -Force
$bin = Get-ChildItem -Path $extract -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
$probe = Get-ChildItem -Path $extract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
Copy-Item $bin.FullName (Join-Path $outDir "ffmpeg.exe") -Force
Copy-Item $probe.FullName (Join-Path $outDir "ffprobe.exe") -Force
Write-Host "Installed to $outDir"
