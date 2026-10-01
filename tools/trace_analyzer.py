#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
22-C S2 特征提取器（模仿学习·学主人打法）—— 平台窗口
读 user://play_traces/trace_*.json → 统计特征报告（站位热图/出手时机/技能序列/走位偏好）
→ 供 S3 转成 AIProfile 参数先验（走 22-A 固化流程，主人拍板）。

用法：python tools/trace_analyzer.py            # 分析全部轨迹
      python tools/trace_analyzer.py <file>    # 分析单条
"""
import json, glob, math, os, sys, io

# 项目目录名以 project.godot config/name 实际为准（实测=battle-ball决竞球）；多候选自动探测
_CANDIDATES = [
    os.path.expandvars(r"%APPDATA%/Godot/app_userdata/Battle Ball/play_traces"),
    os.path.expandvars(r"%APPDATA%/Godot/app_userdata/决竞球battle-ball/play_traces"),
]
USER_DIR = next((c for c in _CANDIDATES if os.path.isdir(c)), _CANDIDATES[0])
GRID = 8  # 热图 8x8


def load_traces(pattern=None):
    paths = [pattern] if pattern else sorted(glob.glob(os.path.join(USER_DIR, "trace_*.json")))
    traces = []
    for p in paths:
        try:
            traces.append(json.load(io.open(p, encoding="utf-8")))
        except Exception as e:
            print(f"⚠ {p}: {e}")
    return traces


def heatmap(traces):
    """站位热图（归一化场地坐标 → 8x8；场地 -650..650 x -390..390）。"""
    grid = [[0] * GRID for _ in range(GRID)]
    n = 0
    for t in traces:
        for s in t.get("samples", []):
            if "pos" not in s:
                continue
            x, y = s["pos"]
            gx = min(GRID - 1, max(0, int((float(x) + 650) / 1300 * GRID)))
            gy = min(GRID - 1, max(0, int((float(y) + 390) / 780 * GRID)))
            grid[gy][gx] += 1
            n += 1
    if n == 0:
        return grid, 0
    return [[round(c * 100.0 / n, 1) for c in row] for row in grid], n


def timing(traces):
    """持球→出手延迟分布 + 技能键时机（持球状态下的比例）。"""
    delays = []
    skill_while_carry = 0
    skill_total = 0
    for t in traces:
        last_catch = None
        last_carry = False
        for ev in t.get("events", []):
            if ev.get("ev") == "catch" and ev.get("who") == t.get("controlled"):
                last_catch = ev["t"]
            elif ev.get("ev") == "throw" and last_catch is not None:
                delays.append(round(ev["t"] - last_catch, 2))
                last_catch = None
        for s in t.get("samples", []):
            last_carry = bool(s.get("carry"))
        for ev in t.get("events", []):
            if ev.get("ev") == "skill_key":
                skill_total += 1
    return delays, skill_total


def movement(traces):
    """走位偏好：x 半场占比 / 平均速度 / 冲刺占比（speed>200）。"""
    left = right = 0
    speeds = []
    for t in traces:
        for s in t.get("samples", []):
            if "pos" not in s:
                continue
            if s["pos"][0] < 0:
                left += 1
            else:
                right += 1
            if "speed" in s:
                speeds.append(float(s["speed"]))
    avg_speed = sum(speeds) / len(speeds) if speeds else 0
    sprint = sum(1 for v in speeds if v > 200) / len(speeds) * 100 if speeds else 0
    return left, right, avg_speed, sprint


def main():
    pattern = sys.argv[1] if len(sys.argv) > 1 else None
    traces = load_traces(pattern)
    if not traces:
        print(f"⚠ 无轨迹文件（{USER_DIR}）——请先实机打局（--platform-human=0）")
        return
    total_t = sum(t.get("duration", 0) for t in traces)
    print(f"== 22-C S2 特征报告：{len(traces)} 局 / {total_t:.0f}s 游玩 ==")
    hm, n = heatmap(traces)
    print(f"\n【站位热图】（% 占比，8x8；左=A门方向）采样 {n}")
    for row in hm:
        print("  " + " ".join(f"{v:5.1f}" for v in row))
    delays, skill_total = timing(traces)
    if delays:
        delays.sort()
        med = delays[len(delays) // 2]
        print(f"\n【出手时机】持球→投球 {len(delays)} 次：中位 {med}s | 最快 {delays[0]}s | 最慢 {delays[-1]}s")
        print(f"  分布: <0.5s={sum(1 for d in delays if d < 0.5)} 0.5~2s={sum(1 for d in delays if 0.5 <= d < 2)} >2s={sum(1 for d in delays if d >= 2)}")
    else:
        print("\n【出手时机】无投球事件（打局时长不足或未持球投出）")
    print(f"【技能键】按键 {skill_total} 次")
    left, right, avg_speed, sprint = movement(traces)
    print(f"【走位】左半场 {left} / 右半场 {right}（占比 {left*100//max(left+right,1)}%）| 均速 {avg_speed:.0f} | 冲刺占比 {sprint:.0f}%")
    print("\n→ S3 先验转换（站位偏好/时机阈值/技能倾向）待主人看报告认'像我的打法'后进行")


if __name__ == "__main__":
    main()
