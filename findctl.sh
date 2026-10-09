#!/bin/bash
# 用法: findctl.sh <json文件> <关键字...>  — 提取 text 含关键字的控件中心坐标
f="$1"; shift
tr '}' '\n' < "$f" | while IFS= read -r line; do
  for kw in "$@"; do
    if echo "$line" | grep -q "\"text\":\"[^\"]*${kw}\""; then
      t=$(echo "$line" | grep -oE '"text":"[^"]*"' | head -1)
      b=$(echo "$line" | grep -oE '"bounds":"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
      if [ -n "$b" ]; then
        nums=$(echo "$b" | grep -oE '[0-9]+' | tr '\n' ' ')
        set -- $nums
        cx=$(( ($1 + $3) / 2 )); cy=$(( ($2 + $4) / 2 ))
        echo "$t -> center($cx,$cy) $b"
      fi
    fi
  done
done | sort -u