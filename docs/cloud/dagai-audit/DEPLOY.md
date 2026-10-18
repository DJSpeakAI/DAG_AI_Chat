# DAG AI Chat 审计日志双备份服务·部署手册

> 服务器：阿里云 ECS（华北2北京，Ubuntu 22.04，公网 8.152.216.55）
> 服务：python3 标准库零依赖，监听 8787，systemd 常驻自启；脱敏元数据按天存 `/opt/dagai-audit/logs/YYYY-MM-DD.jsonl`
> 字段（不含对话正文）：callId / userHash(unionID哈希) / ts / scene / model / status / errCode
> 正本：`server.py` + `dagai-audit.service`（本目录）；下方命令由正本经 gzip+base64 生成

## 用户操作（Workbench 网页终端，逐条粘贴、每条回车后等"第X步完成"再放下一条）

```bash
# 第0步：若终端残留上次卡住的粘贴，先按一次 Ctrl+C，再输入 clear 回车

# 第1步：清理旧现场+建目录
sudo rm -rf /opt/dagai-audit /etc/systemd/system/dagai-audit.service && sudo mkdir -p /opt/dagai-audit/logs && echo "=== 第1步完成"

# 第2步：生成鉴权 Token 存文件
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | sudo tee /opt/dagai-audit/token.txt > /dev/null && echo "=== 第2步完成 token已生成"

# 第3步：写入 server.py（gzip+base64 单行，防多行粘贴断裂）
echo 'H4sIAAAAAAACA5VWX28TRxB/t+TvMAihvYPz2SRRiNxepfxrEjVtEFgqEUXW5m7O3uS8e91dk0QoDy2toFUi+sIfofYhgqqVKqCNeCiqUb8MNuYpX6HaOztcHCcN6wffzc5v5jezM7N39kyxqWRxhfEi8psQb+q64KP53FmYmZyDyQWYrlMN7ee73ee7nYe/tv992L633X56580/rzs/77R/3N1v3e1+91fn/r3297c79//s7Dzfb22/+Xun/dMf7Revui9+6Tx70nlwZ7/1gzH67vbvb1/v7bced3/7BgLhq6IfiWZQDGiNsgJtBkwXZ2YvLy4tu41gv3V3hSocH4P2zv3u7nbnwat2695+a/vdoz34Usi1FeR+HdpPH3d3t9/uPeq+fNl58Kz75NvEGWvEQmpYVYI7IFQ+F0rRgIBq1KyB0Nvuv/e261rHrkJ5E2VfY4oqnK9ULl/Br5uo9DzlQYTSgUpdIg0Yr5nNqwkkn8vnpiavzoIHpChinQ2L5HOLS3PVmYUr4EGidAFIMRI1RfK5zyevVaeWZpbBg/ExOA8XSyNjxliAIUSCBlUt1pBbdjmfAwDQcrP3ZNY603UQMXLrwGyi7uoNTWygCsKMtlkSdVNyCF0TgWW7SksWW3aqhBs+xhpmkz8meAbbwxFiuFWWPpv9ArxD/Izcj6hSMG8Nz1s/hDSyWrWBStEaWgqj0IHz1C5DTJUyhvpqVXOEPQVfBOiAWFm1M7RWRLAJXnLSbtBsxMoyCi5yo90Pyyxjw1XIg6pEFQuu0DIqQzXqSAOUFpkWXCPXhcpmjMQBQuM4Yj41mSkaj+RU6EXkNV0nDigtrQi5ZTjb9iD2PVQd4b0esgjddck0puhsjgJRnZutJEnKZoaFKTamug6eqco60kjXyUBBJEppnkdKJQduEbFGylCRTXSAmH5gPpIykGxBb2UYYqTweJtjpbEDm5/SSOHWIPnLS1f/h/0Zw57GzLQM+SBXH/Xq9pBhLjSkFSxkiu/l3a2htsi1wgytFSqmqs2hE9v4T/RPcj162LUDpKFqJm0rNICkRcgwOhw8YFxbR2kcKZ+SbfiW7MOxwMcelMwGh0+gP0tOIlo6iWiUOhvG9PDgSc6PatrvPTMJVBqFTIo1GS88W+UnDJcPI5m03tCz1dhQ4KXEWAhMMa405T5aRuRAxJS2k4KF60Zy4z1WKLdB1zBgUlm9Ye0AbjClq2LNM92QCSWgm6mb5P5wuVhPJ2loXi1ybrlwrlE4F2Tng881eFAaNrqFSsrcXRWMv/dtfFwA4ppoI2Kb8UMcSAYb4zWPNHVYmBg+40MhgWlgPM3IwG6mCzIJYtqBgPnaLoMvuGa8iUdhUqyDB7eObphFfBpFCwEpJ4OO6bSMe8Kkkezr5fGxG84x8KZCOU9VfcDAgbhvYnTkWBNakTL0gVolTXOcrvKR44CvVHYKRw0RYDQATmWnCFRpqptq0HUq7MMvjh8LRymnRTBIvS892f/WUVHYu1cyV6gU66bSVFNilSqfMS/pQtvU41eHbj3IVPcFDy4O3FvHXiuclA0mvQuGfE1ZFim5yY84MHFp4pLtwLydfp1VQyHR6Nj/AQ7cqKbBCgAA' | base64 -d | gunzip | sudo tee /opt/dagai-audit/server.py > /dev/null && echo "=== 第3步完成 server.py已写入"

# 第4步：装 systemd + 启动 + 自检（出现 {"ok": true...} 即成功）
echo 'W1VuaXRdDQpEZXNjcmlwdGlvbj1EQUdBSSBBdWRpdCBMb2cgQmFja3VwIFNlcnZpY2UNCkFmdGVyPW5ldHdvcmsudGFyZ2V0DQoNCltTZXJ2aWNlXQ0KRXhlY1N0YXJ0PS91c3IvYmluL3B5dGhvbjMgL29wdC9kYWdhaS1hdWRpdC9zZXJ2ZXIucHkNClJlc3RhcnQ9YWx3YXlzDQpSZXN0YXJ0U2VjPTMNCg0KW0luc3RhbGxdDQpXYW50ZWRCeT1tdWx0aS11c2VyLnRhcmdldA==' | base64 -d | sudo tee /etc/systemd/system/dagai-audit.service > /dev/null && sudo systemctl daemon-reload && sudo systemctl enable --now dagai-audit && sleep 1 && curl -s http://127.0.0.1:8787/health && echo " === 第4步完成"

# 第5步：显示 Token（发给 AI，App 端上报用）
sudo cat /opt/dagai-audit/token.txt
```

## 阿里云控制台放行端口（GUI）

ECS 实例页 → 顶部「安全组」标签 → 配置规则 → 入方向 → 手动添加：端口 `8787/8787`、源 `0.0.0.0/0`、描述 `dagai-audit` → 保存。
外网验证：浏览器开 `http://8.152.216.55:8787/health`。

## 运维速查

```bash
sudo systemctl status dagai-audit        # 看状态
sudo systemctl restart dagai-audit       # 重启
sudo tail -5 /opt/dagai-audit/logs/*.jsonl   # 看最新日志
sudo cat /opt/dagai-audit/token.txt      # 查 Token
```