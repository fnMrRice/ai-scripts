#!/bin/bash
# AI自动生成：将.gz文件批量转换为.xz文件

# 如果提供了文件参数，处理指定文件；否则处理目录中所有.gz文件
if [ $# -gt 0 ]; then
  # 处理指定的文件
  for file in "$@"; do
    [ -e "$file" ] || continue
    if [[ "$file" == *.gz ]]; then
      xzfile="${file%.gz}.xz"
      gunzip -c "$file" | xz -z - > "$xzfile"
    fi
  done
else
  # 处理目录中所有.gz文件
  for file in *.gz; do
    [ -e "$file" ] || continue
    xzfile="${file%.gz}.xz"
    gunzip -c "$file" | xz -z - > "$xzfile"
  done
fi
