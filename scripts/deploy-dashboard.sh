#!/bin/sh
# 一键部署「DAGAI 后台数据」看板到阿里云 ECS
# 用法：sh scripts/deploy-dashboard.sh [--force]
#   --force  本地与服务器内容一致时也强制上传并重启
# 正本：docs/cloud/dashboard-v2/  →  服务器：/opt/dagai-dash（systemd: dagai-dash）
set -eu

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
LOCAL_DIR="$ROOT_DIR/docs/cloud/dashboard-v2"
KEY="$HOME/.ssh/dagai_ecs_key"
HOST="root@8.152.216.55"
REMOTE_DIR="/opt/dagai-dash"
SERVICE="dagai-dash"
PORT="8766"
FILES="server.js index.html"
FORCE=0
if [ "${1:-}" = "--force" ]; then FORCE=1; fi

fail() { echo "[deploy] 失败：$*" >&2; exit 1; }
ok()   { echo "[deploy] $*"; }

[ -f "$KEY" ] || fail "找不到 SSH 私钥 $KEY"
for f in $FILES; do
  [ -f "$LOCAL_DIR/$f" ] || fail "找不到本地文件 $LOCAL_DIR/$f"
done

SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SCP="scp -i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

ok "1/6 检查服务器连通性"
$SSH "$HOST" "systemctl is-active --quiet $SERVICE" || fail "服务 $SERVICE 未运行或无法连接"

ok "2/6 比对本地与服务器 MD5"
REMOTE_MD5=$($SSH "$HOST" "cd $REMOTE_DIR && md5sum $FILES 2>/dev/null" || true)
LOCAL_MD5=$(cd "$LOCAL_DIR" && md5sum $FILES)
if [ "$FORCE" -eq 0 ] && [ "$REMOTE_MD5" = "$LOCAL_MD5" ]; then
  ok "内容一致，跳过上传（如需强制部署加 --force）"
else
  ok "3/6 备份服务器旧版本"
  STAMP=$(date +%Y%m%d-%H%M%S)
  $SSH "$HOST" "cd $REMOTE_DIR && for f in $FILES; do cp -p \$f \$f.bak-$STAMP; done" || fail "远程备份失败"

  ok "4/6 上传 $FILES"
  for f in $FILES; do
    $SCP "$LOCAL_DIR/$f" "$HOST:$REMOTE_DIR/$f" || fail "上传 $f 失败"
  done
  $SSH "$HOST" "cd $REMOTE_DIR && chmod 644 $FILES"

  ok "5/6 重启 $SERVICE"
  $SSH "$HOST" "systemctl restart $SERVICE && sleep 2 && systemctl is-active --quiet $SERVICE" || fail "重启失败"

  NEW_MD5=$($SSH "$HOST" "cd $REMOTE_DIR && md5sum $FILES")
  [ "$NEW_MD5" = "$LOCAL_MD5" ] || fail "上传后 MD5 不一致：$NEW_MD5"
  ok "MD5 校验通过"
fi

ok "6/6 健康检查"
CODE=$($SSH "$HOST" "curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:$PORT/")
[ "$CODE" = "200" ] || fail "健康检查异常（HTTP $CODE）"
ok "部署完成：http://8.152.216.55:$PORT/ 已就绪（HTTP $CODE）"
