# -*- coding: utf-8 -*-
"""生成代码地图（func→行号 索引），输出 docs/code_map.md。
用法: python tools/gen_code_map.py
"""
import os, re, io
from datetime import date

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN = os.path.join(ROOT, "scripts")
DETAILED = ("battle", "core", "systems", "battle3d", "ui")   # 逐函数列行号
BRIEF = ("test", "test3d", "ai", "dev_tools", "hooks", "tools", "data")  # 只列文件摘要

RE_FUNC = re.compile(r'^(?:static\s+)?func\s+(\w+)')
RE_SIGNAL = re.compile(r'^signal\s+(\w+)')
RE_SECTION = re.compile(r'^#\s*[-=]{3,}\s*(\S.*?)\s*[-=]{3,}\s*$')


def scan_file(path, detailed):
    n_lines, n_func = 0, 0
    entries = []
    with io.open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f, 1):
            n_lines = i
            s = line.strip()
            m = RE_FUNC.match(s)
            if m:
                n_func += 1
                if detailed:
                    entries.append("L%d func %s" % (i, m.group(1)))
                continue
            if not detailed:
                continue
            m = RE_SIGNAL.match(s)
            if m:
                entries.append("L%d signal %s" % (i, m.group(1)))
                continue
            m = RE_SECTION.match(s)
            if m:
                entries.append("L%d ---- %s ----" % (i, m.group(1)))
    return n_lines, n_func, entries


def main():
    out = ["# 代码地图（func → 行号 索引）",
           "",
           "> 自动生成于 %s。刷新：`python tools/gen_code_map.py`" % date.today().isoformat(),
           "> ⚠ 用法：**grep 本文件找函数名拿行号，禁止整读本文件**；拿到行号后用 Read 的 offset/limit 只读源码目标段 ±80 行。",
           ""]
    groups = {}
    for dirpath, _dirnames, filenames in os.walk(SCAN):
        rel = os.path.relpath(dirpath, SCAN).replace("\\", "/")
        top = "" if rel == "." else rel.split("/")[0]
        for fn in sorted(filenames):
            if not fn.endswith(".gd"):
                continue
            relpath = "scripts/" + (rel + "/" if rel != "." else "") + fn
            detailed = top in DETAILED
            n, nf, entries = scan_file(os.path.join(dirpath, fn), detailed)
            groups.setdefault(top or "(根)", []).append((relpath, n, nf, entries, detailed))

    total_lines = total_files = 0
    for top in sorted(groups):
        files = groups[top]
        detailed = files[0][4]
        out.append("## %s（%s）" % (top, "详细层" if detailed else "摘要层"))
        out.append("")
        for relpath, n, nf, entries, det in sorted(files):
            total_lines += n
            total_files += 1
            if det:
                out.append("### %s — %d行 — %d func" % (relpath, n, nf))
                out.extend(entries)
                out.append("")
            else:
                out.append("- %s — %d行 — %d func" % (relpath, n, nf))
        out.append("")
    out.insert(5, "> 全项目 %d 个脚本 / %d 行（不含 .uid）" % (total_files, total_lines))

    dst = os.path.join(ROOT, "docs", "code_map.md")
    with io.open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("written:", dst, "files:", total_files, "lines:", total_lines)


if __name__ == "__main__":
    main()
