# build-server.ps1 - DAG_AI_Chat LAN build server (Windows / DevEco required)
# Usage: right-click -> "Run with PowerShell" (auto self-elevates as Admin, keep window open)
# Endpoints:
#   GET  /            -> status json
#   POST /build       -> git sync + hvigorw assembleHap, returns signed HAP bytes
#   POST /install     -> build + hdc install to all connected devices, returns report

$ErrorActionPreference = "Continue"
$Port = 8765
$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- self elevate to admin (HttpListener + firewall need it) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host "== DAG_AI_Chat build server on port $Port ==" -ForegroundColor Cyan
Write-Host "Repo: $RepoDir"

# --- locate hvigorw (edit here if auto-detect fails) ---
$HvigorCandidates = @(
    "$env:DEVECO_HOME\tools\hvigor\bin\hvigorw.bat",
    "$env:ProgramFiles\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat",
    "${env:ProgramFiles(x86)}\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat",
    "D:\HarmonyOS\IDE\DevEco Studio\tools\hvigor\bin\hvigorw.bat",
    "D:\DevEco Studio\tools\hvigor\bin\hvigorw.bat",
    "C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
)
$Hvigorw = $null
foreach ($c in $HvigorCandidates) { if (Test-Path $c) { $Hvigorw = $c; break } }
if (-not $Hvigorw) { $cmd = Get-Command hvigorw.bat -ErrorAction SilentlyContinue; if ($cmd) { $Hvigorw = $cmd.Source } }
if (-not $Hvigorw) {
    $found = Get-ChildItem -Path "C:\","D:\" -Filter "hvigorw.bat" -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $Hvigorw = $found.FullName }
}
if ($Hvigorw) { Write-Host "hvigorw: $Hvigorw" -ForegroundColor Green }
else { Write-Host "WARN: hvigorw.bat not found by auto-detect; it will retry per request. If build fails, open build-server.ps1 and add your DevEco path to `$HvigorCandidates`" -ForegroundColor Yellow }

# --- locate hdc (DevEco sdk toolchains) ---
$Hdc = $null
$hdcSearch = @("$env:ProgramFiles\Huawei\DevEco Studio\sdk", "D:\HarmonyOS", "D:\DevEco Studio", "C:\DevEco Studio")
foreach ($root in $hdcSearch) {
    if (Test-Path $root) {
        $f = Get-ChildItem -Path $root -Filter "hdc.exe" -Recurse -Depth 6 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { $Hdc = $f.FullName; break }
    }
}
if ($Hdc) { Write-Host "hdc: $Hdc" -ForegroundColor Green }

# --- firewall rule (idempotent) ---
netsh advfirewall firewall delete rule name="DagBuild8765" | Out-Null
netsh advfirewall firewall add rule name="DagBuild8765" dir=in action=allow protocol=TCP localport=$Port | Out-Null

function Sync-Repo {
    Push-Location $RepoDir
    git fetch codearts main 2>&1 | ForEach-Object { Write-Host "  git: $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  git fetch FAILED (credential issue?) - building last synced code" -ForegroundColor Red
    } else {
        git reset --hard codearts/main 2>&1 | Out-Null
    }
    Pop-Location
}

function Do-Build {
    if (-not $Hvigorw) { return @{ ok = $false; err = "hvigorw.bat not found; edit `$HvigorCandidates` in build-server.ps1" } }
    Sync-Repo
    Push-Location $RepoDir
    & $Hvigorw assembleHap --mode module -p product=default -p debuggable=true --no-daemon 2>&1 | Tee-Object -Variable buildLog | Out-Null
    Pop-Location
    $hap = Get-ChildItem -Path (Join-Path $RepoDir "entry\build\default\outputs\default") -Filter "*-signed.hap" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($hap) { return @{ ok = $true; hap = $hap.FullName; log = ($buildLog | Select-Object -Last 30) -join "`n" } }
    return @{ ok = $false; err = "build failed"; log = ($buildLog | Select-Object -Last 40) -join "`n" }
}

function Do-Install {
    $b = Do-Build
    if (-not $b.ok) { return $b }
    if (-not $Hdc) { return @{ ok = $false; err = "hdc.exe not found" } }
    & $Hdc tconn 192.168.2.16:5555 2>&1 | Out-Null
    & $Hdc tconn 192.168.2.9:5555 2>&1 | Out-Null
    $devs = (& $Hdc list targets) | Where-Object { $_ -match "^\[?" -and $_.Trim("[]") -ne "empty" }
    $report = @()
    foreach ($d in $devs) {
        $id = $d.Trim("[]")
        if ($id -eq "empty" -or [string]::IsNullOrWhiteSpace($id)) { continue }
        $r = & $Hdc -t $id install -r $b.hap 2>&1
        $report += "$id => $r"
    }
    return @{ ok = $true; hap = $b.hap; devices = $report -join "`n" }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()
Write-Host "Listening on http://+:$Port  (Ctrl+C to stop)" -ForegroundColor Green

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request; $res = $ctx.Response
    try {
        if ($req.HttpMethod -eq "GET") {
            $bytes = [Text.Encoding]::UTF8.GetBytes(('{"status":"running","hvigorw":"' + $Hvigorw + '","hdc":"' + $Hdc + '"}'))
            $res.ContentType = "application/json"; $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        elseif ($req.HttpMethod -eq "POST" -and $req.Url.AbsolutePath -eq "/build") {
            Write-Host "[$(Get-Date -Format HH:mm:ss)] POST /build -> building..." -ForegroundColor Cyan
            $b = Do-Build
            if ($b.ok) {
                $hapBytes = [IO.File]::ReadAllBytes($b.hap)
                $res.ContentType = "application/octet-stream"
                $res.Headers["Content-Disposition"] = "attachment; filename=DAG-AI-Chat-signed.hap"
                $res.OutputStream.Write($hapBytes, 0, $hapBytes.Length)
                Write-Host "  OK -> $(Split-Path -Leaf $b.hap) ($($hapBytes.Length) bytes)" -ForegroundColor Green
            } else {
                $bytes = [Text.Encoding]::UTF8.GetBytes("BUILD FAILED:`n$($b.err)`n$($b.log)")
                $res.StatusCode = 500; $res.ContentType = "text/plain; charset=utf-8"
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "  FAILED" -ForegroundColor Red
            }
        }
        elseif ($req.HttpMethod -eq "POST" -and $req.Url.AbsolutePath -eq "/install") {
            Write-Host "[$(Get-Date -Format HH:mm:ss)] POST /install -> building + installing..." -ForegroundColor Cyan
            $r = Do-Install
            $bytes = [Text.Encoding]::UTF8.GetBytes(($r | ConvertTo-Json -Depth 3))
            $res.ContentType = "application/json; charset=utf-8"
            if (-not $r.ok) { $res.StatusCode = 500 }
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        else {
            $res.StatusCode = 404
        }
    } catch {
        try { $res.StatusCode = 500 } catch {}
    }
    finally { $res.OutputStream.Close() }
}