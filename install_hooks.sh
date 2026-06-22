#!/bin/bash
# 决竞球 - 一键安装 git 钩子
# --------------------------------------------------------------------------
# 用法: ./install_hooks.sh
# 作用: 把 scripts/hooks/pre-commit 复制到 .git/hooks/ 并赋予执行权限。
#       新克隆仓库 / 重装系统 / 钩子丢失后跑一次即可。
# --------------------------------------------------------------------------

cd "$(dirname "$0")"

SRC="./scripts/hooks/pre-commit"
DST="./.git/hooks/pre-commit"

if [ ! -f "$SRC" ]; then
  echo "✗ 找不到钩子源文件: $SRC"
  exit 1
fi

if [ ! -d "./.git/hooks" ]; then
  echo "✗ 当前目录不是 git 仓库（找不到 .git/hooks/）"
  exit 1
fi

mkdir -p "./.git/hooks"
cp "$SRC" "$DST"
chmod +x "$DST"

echo "✓ git pre-commit 钩子已安装到 $DST"
echo ""
echo "现在每次 git commit 含 .gd 代码时，会自动跑 verify.sh 验证。"
echo "（验证不过会拒绝提交；紧急跳过用 git commit --no-verify）"
