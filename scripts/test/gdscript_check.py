#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""GDScript 语法检查 - 抓真正会崩的错误"""

import sys
import re

def check_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    errors = []
    
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or '"""' in stripped:
            continue
        
        # 检查: 多值 Python格式化 "% (...)" → 应该 "% [...]"
        m = re.search(r'"[^"]*%[^"]*"\s*%\s*\(([^)]+)\)', stripped)
        if m:
            inside = m.group(1).strip()
            if ',' in inside:
                errors.append(f'L{i}: 多值格式化 % (a,b) → GDScript用 % [a,b]')
    
    return errors

if __name__ == '__main__':
    files = sys.argv[1:]
    if not files:
        print("用法: python gdscript_check.py <file.gd> ...")
        sys.exit(1)
    
    total = 0
    for f in files:
        errs = check_file(f)
        if errs:
            print(f"\n=== {f} ===")
            for e in errs:
                print(f"  {e}")
            total += len(errs)
        else:
            print(f"  {f}: OK")
    
    if total > 0:
        print(f"\n共 {total} 个问题")
        sys.exit(1)
    else:
        print("\n全部通过")
        sys.exit(0)
