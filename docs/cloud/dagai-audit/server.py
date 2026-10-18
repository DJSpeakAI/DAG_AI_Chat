#!/usr/bin/env python3
# DAG AI Chat 审计日志双备份服务（脱敏元数据，不含对话正文）
# 部署：见 docs/cloud/dagai-audit/DEPLOY.md（base64 单行方式，防 Workbench 多行粘贴断裂）
import json, os
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = '/opt/dagai-audit'
LOG_DIR = BASE + '/logs'
MAX_BODY = 64 * 1024

def load_token():
    try:
        with open(BASE + '/token.txt') as f:
            return f.read().strip()
    except Exception:
        return ''

TOKEN = load_token()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/health':
            self._json(200, {'ok': True, 'service': 'dagai-audit'})
        else:
            self._json(404, {'ok': False})

    def do_POST(self):
        if self.path != '/api/log':
            self._json(404, {'ok': False}); return
        if not TOKEN or self.headers.get('X-Dag-Token', '') != TOKEN:
            self._json(403, {'ok': False, 'msg': 'bad token'}); return
        n = int(self.headers.get('Content-Length', 0) or 0)
        if n <= 0 or n > MAX_BODY:
            self._json(400, {'ok': False, 'msg': 'bad length'}); return
        try:
            data = json.loads(self.rfile.read(n))
        except Exception:
            self._json(400, {'ok': False, 'msg': 'bad json'}); return
        items = data if isinstance(data, list) else [data]
        os.makedirs(LOG_DIR, exist_ok=True)
        day = datetime.now().strftime('%Y-%m-%d')
        cnt = 0
        with open(os.path.join(LOG_DIR, day + '.jsonl'), 'a', encoding='utf-8') as f:
            for it in items:
                if not isinstance(it, dict): continue
                row = {
                    'callId': str(it.get('callId', ''))[:64],
                    'userHash': str(it.get('userHash', ''))[:32],
                    'ts': it.get('ts', 0),
                    'scene': str(it.get('scene', ''))[:32],
                    'model': str(it.get('model', ''))[:64],
                    'status': str(it.get('status', ''))[:16],
                    'errCode': str(it.get('errCode', ''))[:64],
                }
                f.write(json.dumps(row, ensure_ascii=False) + '\n')
                cnt += 1
        self._json(200, {'ok': True, 'n': cnt})

ThreadingHTTPServer(('0.0.0.0', 8787), H).serve_forever()