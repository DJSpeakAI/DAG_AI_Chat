# ============================================================
# DAG AI Chat · 种子用户兑换码生成器（★ 0.194.0）
# 用法：powershell -File scripts\gen-redeem-codes.ps1 -Count 200
# 产出：
#   <项目根>\兑换码清单.txt   —— 明文清单（用户保管；勿打包进应用、勿提交公开仓库）
#   scripts\redeem-hashes.txt —— SHA256 哈希（嵌入 ChatModel.ets 的 REDEEM_CODE_HASHES）
# 码格式：DAGAI-XXXXX-XXXXX（32 字符集，剔除 0/O/1/I 防抄写混淆；每码 +90 天，可叠加，一次性）
# ============================================================
param(
  [int]$Count = 200,
  [string]$ProjectDir = (Split-Path $PSScriptRoot -Parent)
)

$charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$sha = [System.Security.Cryptography.SHA256]::Create()

function New-Code {
  $bytes = New-Object byte[] 10
  $rng.GetBytes($bytes)
  $p1 = -join (0..4 | ForEach-Object { $charset[$bytes[$_] % 32] })
  $p2 = -join (5..9 | ForEach-Object { $charset[$bytes[$_] % 32] })
  return "DAGAI-$p1-$p2"
}

$codes = New-Object System.Collections.Generic.List[string]
while ($codes.Count -lt $Count) {
  $c = New-Code
  if (-not $codes.Contains($c)) { $codes.Add($c) }
}

$listLines = @(
  "DAG AI Chat · 种子用户兑换码清单",
  "生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "数量：$Count｜每码 +90 天会员权益｜可叠加（连续兑换顺延）｜每码一次性使用",
  "兑换入口：应用内 边栏 → 账单 → 兑换码",
  "注意：本文件是唯一明文清单，妥善备份；勿提交公开仓库、勿打包进应用",
  ""
)
$hashLines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $codes.Count; $i++) {
  $code = $codes[$i]
  $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($code))).Replace("-", "").ToLower()
  $listLines += ("{0:d3}  {1}" -f ($i + 1), $code)
  $hashLines.Add($hash)
}

$listPath = Join-Path $ProjectDir "兑换码清单.txt"
$hashPath = Join-Path $PSScriptRoot "redeem-hashes.txt"
[System.IO.File]::WriteAllLines($listPath, $listLines, [Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllLines($hashPath, $hashLines, [Text.UTF8Encoding]::new($false))

Write-Host "OK 清单: $listPath"
Write-Host "OK 哈希: $hashPath ($($hashLines.Count) 个)"
Write-Host "首码: $($codes[0])  哈希: $($hashLines[0])"
