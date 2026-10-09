import json, sys

path = sys.argv[1]
kws = sys.argv[2:]
data = json.loads(open(path, encoding='utf-8').read())

def center(b):
    try:
        import re
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        x1, y1, x2, y2 = map(int, m.groups())
        return f'({(x1+x2)//2},{(y1+y2)//2}) {b}'
    except Exception:
        return b

def walk(node):
    attrs = node.get('attributes', {})
    text = attrs.get('text', '')
    for kw in kws:
        if kw in text:
            print(f'{text[:24]:26s} {center(attrs.get("bounds",""))} visible={attrs.get("visible")}')
            break
    for c in node.get('children', []):
        walk(c)

walk(data)