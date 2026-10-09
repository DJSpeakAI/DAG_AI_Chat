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
    "E:\software\DevEco Studio\tools\hvigor\bin\hvigorw.bat",
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
    $found = Get-ChildItem -Path "C:\","D:\","E:\" -Filter "hvigorw.bat" -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $Hvigorw = $found.FullName }
}
if ($Hvigorw) { Write-Host "hvigorw: $Hvigorw" -ForegroundColor Green }
else { Write-Host 'WARN: hvigorw.bat not found by auto-detect; it will retry per request. If build fails, edit the $HvigorCandidates list in build-server.ps1' -ForegroundColor Yellow }

# --- locate hdc (DevEco sdk toolchains) ---
$Hdc = $null
$hdcSearch = @("E:\software\DevEco Studio\sdk", "$env:ProgramFiles\Huawei\DevEco Studio\sdk", "D:\HarmonyOS", "D:\DevEco Studio", "C:\DevEco Studio")
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
    if (-not $Hvigorw) { return @{ ok = $false; err = 'hvigorw.bat not found; edit the $HvigorCandidates list in build-server.ps1' } }
    Sync-Repo
    # 0.214.1r fake-success fix #1: delete stale signed hap BEFORE compiling, so a failed build can never ship an old hap
    $outDir = Join-Path $RepoDir "entry\build\default\outputs\default"
    if (Test-Path $outDir) { Remove-Item "$outDir\*-signed.hap" -Force -ErrorAction SilentlyContinue }
    Push-Location $RepoDir
    & $Hvigorw assembleHap --mode module -p product=default -p debuggable=true --no-daemon 2>&1 | Tee-Object -Variable buildLog | Out-Null
    $hvigorExit = $LASTEXITCODE
    Pop-Location
    # 0.214.1r fake-success fix #2: hvigor non-zero exit = compile failed, report error with log
    if ($hvigorExit -ne 0) {
        return @{ ok = $false; err = "COMPILE FAILED (hvigorw exit $hvigorExit)"; log = ($buildLog | Select-Object -Last 45) -join "`n" }
    }
    $hap = Get-ChildItem -Path $outDir -Filter "*-signed.hap" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($hap) { return @{ ok = $true; hap = $hap.FullName; log = ($buildLog | Select-Object -Last 30) -join "`n" } }
    return @{ ok = $false; err = "build failed (no signed hap produced)"; log = ($buildLog | Select-Object -Last 40) -join "`n" }
}

function Get-KnownDevices {
    $kf = Join-Path $RepoDir ".known-devices"
    if (Test-Path $kf) { return @(Get-Content $kf | Where-Object { $_ -match ":" }) }
    return @()
}
function Add-KnownDevice($addr) {
    $kf = Join-Path $RepoDir ".known-devices"
    $known = Get-KnownDevices
    if ($known -notcontains $addr) { Add-Content -Path $kf -Value $addr }
}
function Get-DeviceList {
    if (-not $Hdc) { return ,@() }
    foreach ($a in (Get-KnownDevices)) { & $Hdc tconn $a 2>&1 | Out-Null }
    $targets = (& $Hdc list targets) | Where-Object { $_ -match ":" }
    $list = @()
    foreach ($t in $targets) {
        $id = $t.Trim("[]")
        $model = (& $Hdc -t $id shell param get const.product.model 2>$null)
        $list += @{ addr = $id; model = "$model" }
    }
    return ,$list
}
function Do-Install($target) {
    $b = Do-Build
    if (-not $b.ok) { return $b }
    if (-not $Hdc) { return @{ ok = $false; err = "hdc.exe not found" } }
    $devs = @()
    if ($target) {
        & $Hdc tconn $target 2>&1 | Out-Null
        Add-KnownDevice $target
        $devs = @($target)
    } else {
        foreach ($a in (Get-KnownDevices)) { & $Hdc tconn $a 2>&1 | Out-Null }
        $devs = @((& $Hdc list targets) | Where-Object { $_ -match ":" } | ForEach-Object { $_.Trim("[]") })
    }
    $report = @()
    foreach ($id in $devs) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $r = & $Hdc -t $id install -r $b.hap 2>&1
        $report += "$id => $(($r -join ' '))"
        if (($r -join ' ') -match "successfully") {
            Start-Sleep -Milliseconds 800
            $s = & $Hdc -t $id shell aa start -a EntryAbility -b com.example.dag_ai_chat 2>&1
            $report += "$id => 自动启动: $(($s -join ' '))"
        }
    }
    $joined = $report -join "`n"
    $good = $joined -match "successfully"
    $bad = $joined -match "failed|error:"
    return @{ ok = ($good -and -not $bad); hap = $b.hap; devices = $joined }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()
Write-Host "Listening on http://+:$Port  (Ctrl+C to stop)" -ForegroundColor Green

$PageHtml = @'
<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DAG AI Chat 一键装机</title>
<style>
body{background:#160D26;color:#E8E0F0;font-family:system-ui;margin:0;padding:24px;max-width:640px;margin:auto}
h1{font-size:22px;margin:8px 0} .sub{color:#9C8AB8;font-size:13px;margin-bottom:16px}
.card{background:#221539;border:1px solid #3A2A5C;border-radius:12px;padding:14px 16px;margin:10px 0;display:flex;align-items:center;gap:12px;cursor:pointer}
.card.sel{border-color:#8B5CF6;background:#2A1B4A}
.ico{font-size:26px} .nm{font-weight:600} .ad{color:#9C8AB8;font-size:12px}
input[type=text]{width:100%;box-sizing:border-box;background:#221539;border:1px solid #3A2A5C;border-radius:10px;color:#E8E0F0;padding:12px;font-size:15px;margin-top:6px}
.go{width:100%;background:linear-gradient(135deg,#8B5CF6,#6D28D9);color:#fff;border:none;border-radius:12px;padding:15px;font-size:16px;font-weight:700;margin-top:16px;cursor:pointer}
.go:disabled{opacity:.5}
#res{white-space:pre-wrap;background:#1A1030;border-radius:12px;padding:14px;margin-top:14px;font-size:13px;display:none}
.ok{color:#4ADE80}.bad{color:#F87171}
.hint{color:#6B5B8A;font-size:11px;margin-top:14px;text-align:center}
</style></head><body>
<h1>📚 DAG AI Chat · 一键装机</h1>
<div class="sub">老机器 DevEco 编译（约 1 分钟）→ 自动安装到设备</div>
<div id="devs"><div class="sub">探测设备中…</div></div>
<div class="card" id="spare-pad"><div class="ico">📟</div><div style="flex:1"><div class="nm">pad 备用（IP 变了改这里）</div><input type="text" class="sparein" data-key="pad" placeholder="192.168.2.x:xxxxx"></div></div>
<div class="card" id="spare-pc"><div class="ico">💻</div><div style="flex:1"><div class="nm">pc 备用（IP 变了改这里）</div><input type="text" class="sparein" data-key="pc" placeholder="192.168.2.x:xxxxx"></div></div>
<input type="text" id="manual" placeholder="手动地址（一次性使用，如 192.168.2.16:38611）">
<button class="go" id="go">🚀 编译并安装</button>
<div id="res"></div>
<div class="hint">选中设备卡片后点安装；都不选 = 全部在线设备 · 装完自动打开 app · 服务 http://192.168.2.15:8765</div>
<script>
var sel=null;
function nameOf(m){m=(m||'').trim();
 if(m.indexOf('SLG')>=0)return '平板 MatePad 11.5s';
 if(m.indexOf('CHZ')>=0)return '手机 畅享 90 Pro';
 return 'Matebook 14'}
function icoOf(m){m=(m||'').trim();
 if(m.indexOf('SLG')>=0)return '📟';
 if(m.indexOf('CHZ')>=0)return '📱';
 return '💻'}
function refresh(){
 fetch('/devices').then(function(r){return r.json()}).then(function(ds){
  var box=document.getElementById('devs');box.innerHTML='';
  if(!ds||!ds.length){box.innerHTML='<div class="sub">没有在线设备——设备的「无线调试」开了吗？可用下方备用卡片填地址</div>';return}
  ds.forEach(function(d){
   var c=document.createElement('div');c.className='card';c.dataset.addr=d.addr;
   c.innerHTML='<div class="ico">'+icoOf(d.model)+'</div><div><div class="nm">'+nameOf(d.model)+'</div><div class="ad">'+d.addr+'</div></div>';
   c.onclick=function(){sel=(sel===d.addr)?null:d.addr;renderSel()};box.appendChild(c)})})
 .catch(function(){document.getElementById('devs').innerHTML='<div class="sub">连不上编译服务（老机器开机了吗？）</div>'})}
function renderSel(){document.querySelectorAll('.card').forEach(function(c){c.classList.toggle('sel',c.dataset.addr===sel && c.dataset.addr)})}
function bindSpare(key){
 var c=document.getElementById('spare-'+key);if(!c)return;
 var inp=c.querySelector('input');
 inp.value=localStorage.getItem('spare-'+key)||'';
 inp.onchange=function(){var v=inp.value.trim();localStorage.setItem('spare-'+key,v);c.dataset.addr=v;if(c.classList.contains('sel'))sel=v};
 inp.onclick=function(e){e.stopPropagation()};
 c.onclick=function(){var v=inp.value.trim();if(!v){inp.focus();return}c.dataset.addr=v;sel=(sel===v)?null:v;renderSel()}}
bindSpare('pad');bindSpare('pc');
function doInstall(){
 var btn=document.getElementById('go'),res=document.getElementById('res');
 var manual=document.getElementById('manual').value.trim();
 var t=manual||sel;
 btn.disabled=true;btn.textContent='⏳ 编译安装中…（约1分钟）';
 res.style.display='block';res.className='';res.textContent='进行中…';
 fetch('/install',{method:'POST',body:t?JSON.stringify({target:t}):''}).then(function(r){return r.json()}).then(function(j){
  res.textContent=(j.ok?'✅ 完成\n':'❌ 失败\n')+(j.devices||j.err||'')+(j.hap?'\n包: '+j.hap:'');
  res.className=j.ok?'ok':'bad'})
 .catch(function(e){res.textContent='请求失败：'+e;res.className='bad'});
 btn.disabled=false;btn.textContent='🚀 编译并安装'}
document.getElementById('go').onclick=doInstall;
refresh();
</script></body></html>
'@

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request; $res = $ctx.Response
    try {
        if ($req.HttpMethod -eq "GET" -and $req.Url.AbsolutePath -eq "/") {
            $bytes = [Text.Encoding]::UTF8.GetBytes($PageHtml)
            $res.ContentType = "text/html; charset=utf-8"; $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        elseif ($req.HttpMethod -eq "GET" -and $req.Url.AbsolutePath -eq "/devices") {
            $list = Get-DeviceList
            $bytes = [Text.Encoding]::UTF8.GetBytes(($list | ConvertTo-Json -Compress))
            $res.ContentType = "application/json; charset=utf-8"; $res.OutputStream.Write($bytes, 0, $bytes.Length)
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
            $reader = New-Object IO.StreamReader($req.InputStream)
            $bodyTxt = $reader.ReadToEnd()
            $target = $null
            try { $j = $bodyTxt | ConvertFrom-Json; if ($j.target) { $target = $j.target } } catch {}
            if ($target) { Write-Host "  target: $target" -ForegroundColor Cyan }
            $r = Do-Install $target
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