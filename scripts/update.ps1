$ErrorActionPreference = "Stop"

$Repo = if ($env:ZPM_UPDATE_REPO) { $env:ZPM_UPDATE_REPO } else { "crnobog69/zpm-bin" }
$InstallDir = if ($env:ZPM_INSTALL_DIR) { $env:ZPM_INSTALL_DIR } else { Join-Path $HOME ".local\bin" }
$AppName = "zpm"

$archRaw = $env:PROCESSOR_ARCHITECTURE
$arch = switch -Regex ($archRaw) {
  "ARM64" { "arm64" }
  default { "amd64" }
}

$tagInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
$tag = $tagInfo.tag_name
if ([string]::IsNullOrWhiteSpace($tag)) {
  throw "Cannot resolve latest release tag for $Repo"
}

$asset = "$AppName-windows-$arch.exe"
$assetUrl = "https://github.com/$Repo/releases/download/$tag/$asset"
$checksumsUrl = "https://github.com/$Repo/releases/download/$tag/checksums.txt"

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zpm-update-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
try {
  $tmpAsset = Join-Path $tmpDir $asset
  $tmpChecksums = Join-Path $tmpDir "checksums.txt"

  Invoke-WebRequest -Uri $assetUrl -OutFile $tmpAsset -UseBasicParsing
  Invoke-WebRequest -Uri $checksumsUrl -OutFile $tmpChecksums -UseBasicParsing

  $expected = $null
  foreach ($line in Get-Content $tmpChecksums) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
    $parts = $trimmed -split '\s+'
    if ($parts.Count -lt 2) { continue }
    $name = $parts[-1].TrimStart("*")
    if ($name -eq $asset) {
      $expected = $parts[0].ToLower().Replace("sha256:", "")
      break
    }
  }
  if ([string]::IsNullOrWhiteSpace($expected)) {
    throw "Missing checksum for $asset in checksums.txt"
  }

  $actual = (Get-FileHash -Path $tmpAsset -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $expected) {
    throw "Checksum mismatch for $asset. expected=$expected actual=$actual"
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -Path $tmpAsset -Destination (Join-Path $InstallDir "$AppName.exe") -Force
  Write-Host "$AppName installed to $(Join-Path $InstallDir "$AppName.exe") ($tag)"
} finally {
  if (Test-Path $tmpDir) {
    Remove-Item -Path $tmpDir -Recurse -Force
  }
}
