#!/bin/sh
# ★ 0.233.0.3 测试台看护脚本（用户在 DevEco Terminal 里执行一次，之后全自动）：
#   ① server.js 代码被更新（agent 改码/发版）→ 5 秒内自动重启服务，无需人工
#   ② 服务意外退出 → 自动拉起
#   ③ 页面【关闭服务】/关 html 30 秒自动关 → 写 .watchdog-skip 标记 → 看护脚本保持关闭不拉起；
#      下次看护脚本拉起新实例时自动清标记，恢复正常看护
# 用法：cd /storage/Users/currentUser/project/DAG_AI_Chat/testing/console && sh watch-server.sh
NODE=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/node/bin/node
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1
echo "[watchdog] 看护已启动（检测周期 5 秒）——server.js 更新自动重启、退出自动拉起；页面【关闭服务】=保持关闭"
while true; do
  M_JS=$(stat -c %Y server.js 2>/dev/null || echo 0)
  P_PID=$(cat server.pid 2>/dev/null)
  ALIVE=0
  [ -n "$P_PID" ] && kill -0 "$P_PID" 2>/dev/null && ALIVE=1
  M_PID=$(stat -c %Y server.pid 2>/dev/null || echo 0)
  if [ "$ALIVE" = "1" ] && [ "$M_JS" -gt "$M_PID" ]; then
    echo "[watchdog] server.js 已更新（mtime $M_JS > 运行实例 $M_PID），自动重启..."
    kill "$P_PID" 2>/dev/null
    sleep 2
    ALIVE=0
  fi
  if [ "$ALIVE" != "1" ]; then
    if [ -f .watchdog-skip ]; then
      sleep 5
      continue
    fi
    echo "[watchdog] 启动测试台服务..."
    nohup "$NODE" server.js >> server.log 2>&1 &
    sleep 3
  fi
  sleep 5
done