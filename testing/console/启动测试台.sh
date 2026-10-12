#!/bin/sh
# ============================================================
# 启动测试台.sh — 桌面唯一入口（双击/终端打开：起服务 + 开浏览器）
# 幂等：服务已在线直接开页面；不在线自动后台拉起（关窗口服务不停）
# 停止服务：在测试台页面点【关闭服务】按钮
# ============================================================
BASE="http://127.0.0.1:8766"
SRV="/storage/Users/currentUser/project/DAG_AI_Chat/testing/console/server.js"
LOG="/storage/Users/currentUser/project/DAG_AI_Chat/testing/console/server.log"

# 本机 node / hdc 不在默认 PATH：显式补上本地工具链目录（否则 node 找不到、服务起不来）
TOOL="/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0"
export PATH="$TOOL/node/bin:$TOOL/sdk/default/openharmony/toolchains:$PATH"

if ! curl -s -m 2 "$BASE/api/health" 2>/dev/null | grep -q '"ok":true'; then
  # 服务不在线：后台拉起（nohup 脱离终端，关窗口服务不停）
  nohup node "$SRV" >> "$LOG" 2>&1 &
  # 等服务上线（最多 20 秒；内部含僵尸自愈可能多花几秒）
  i=0
  while [ $i -lt 20 ]; do
    curl -s -m 1 "$BASE/api/health" 2>/dev/null | grep -q '"ok":true' && break
    sleep 1
    i=$((i+1))
  done
fi

# 复核服务是否真的在线（失败要如实报错，别假报成功）
if ! curl -s -m 2 "$BASE/api/health" 2>/dev/null | grep -q '"ok":true'; then
  echo "❌ 测试台服务启动失败——请查看日志：$LOG"
  echo "（本终端窗口可直接关闭；修好后重新运行本脚本即可）"
  sleep 8
  exit 1
fi

# 打开浏览器到测试台（动态探测本机 hdc 调试口；DevEco 开着即在）
PORT=$(hdc list targets 2>/dev/null | grep '^127\.0\.0\.1:' | head -1)
if [ -n "$PORT" ]; then
  hdc -t "$PORT" shell "aa start -a MainAbility -b com.huawei.hmos.browser -U $BASE/" >/dev/null 2>&1
  echo "✅ 已唤起浏览器打开测试台。本终端窗口可关闭，不影响服务。"
else
  # 调试口不在（DevEco 未开）：仍用系统浏览器兜底
  echo "✅ 测试台服务已在线：请用浏览器打开 $BASE/"
  echo "（本终端窗口可关闭，服务不会停；要停止服务，在页面上点【关闭服务】按钮）"
fi
sleep 5