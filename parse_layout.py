import json, re, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'layout3.json'
s = open(path, encoding='utf-8').read()

# 展开压缩 JSON 树，打印 text + bounds 简表（可按关键字过滤）
kw = sys.argv[2] if len(sys.argv) > 2 else None
data = json.loads(s)

def walk(node):
    attrs = node.get('attributes', {})
    text = attrs.get('text', '')
    bounds = attrs.get('bounds', '')
    t = attrs.get('type', '')
    if text or (kw and kw in json.dumps(node, ensure_ascii=False)):
        if kw is None or (kw and (kw in text)):
            print(f'{t:12s} {text[:30]:32s} {bounds}')
    for c in node.get('children', []):
        walk(c)

walk(data)