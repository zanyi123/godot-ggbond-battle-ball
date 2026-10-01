#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
22-C S3 先验转换器（模仿学习·学主人打法）—— 操球窗口
读主人轨迹（复用 trace_analyzer 的加载与特征口径）→ 生成 AIProfile 参数 diff 建议
（走 22-A 固化流程：建议≠替换，主人拍板后一次性写入）。

映射原则（每条可解释，禁黑盒）：
  出手延迟中位数 → skill_think_interval（思考节拍对齐主人节奏）
  技能键频次/持球 → skill_use_threshold 与 energy_min（主人出手更果断=阈值降）
  均速/冲刺占比 → skill_late_game_bonus/losing_bonus 不动（比赛阶段项无轨迹证据），
                  走位类参数仅给"观察项"不直接改（避免单局过拟合）
  投球延迟方差   → skill_uncertainty_discount（主人稳定=不确定性折价低）

用法：python tools/trace_prior.py [轨迹文件]
产出：控制台 diff 表 + tools/trace_prior_report.md（供主人拍板）
"""
import json, glob, math, os, sys, io, statistics

_CANDIDATES = [
    os.path.expandvars(r"%APPDATA%/Godot/app_userdata/battle-ball决竞球/play_traces"),
    os.path.expandvars(r"%APPDATA%/Godot/app_userdata/决竞球battle-ball/play_traces"),
]
USER_DIR = next((c for c in _CANDIDATES if os.path.isdir(c)), _CANDIDATES[0])

# 现值锚（ai_profile.gd @ 2026-09-30 HEAD；22-A S6 报告参数未固化，以现值为基线）
CURRENT = {
    "skill_think_interval": 0.5,
    "skill_use_threshold": 10.0,
    "skill_energy_min": 10.0,
    "skill_uncertainty_discount": 0.6,
    "skill_reserve_weight": 0.9,
}
# 建议范围护栏（防单局过拟合：每参数限幅）
GUARD = {
    "skill_think_interval": (0.2, 0.5),      # 不慢于现状（事件钩子已提频）
    "skill_use_threshold": (5.0, 10.0),      # 只降不升（学主人果断）
    "skill_energy_min": (0.0, 10.0),         # 只降不升
    "skill_uncertainty_discount": (0.4, 0.6),
    "skill_reserve_weight": (0.7, 0.9),
}


def load_traces(pattern=None):
    paths = [pattern] if pattern else sorted(glob.glob(os.path.join(USER_DIR, "trace_*.json")))
    traces = []
    for p in paths:
        try:
            traces.append(json.load(io.open(p, encoding="utf-8")))
        except Exception as e:
            print(f"⚠ {p}: {e}")
    return traces


def extract(traces):
    """特征提取（与 trace_analyzer 同口径）：投球延迟列表/技能键次数/均速/冲刺占比/采样时长。"""
    delays, skill_keys, speeds, samples_n, throws = [], 0, [], 0, 0
    for t in traces:
        last_catch = None
        for ev in t.get("events", []):
            if ev.get("ev") == "catch" and ev.get("who") == t.get("controlled"):
                last_catch = ev["t"]
            elif ev.get("ev") == "throw" and last_catch is not None:
                delays.append(round(ev["t"] - last_catch, 2))
                throws += 1
                last_catch = None
            elif ev.get("ev") == "skill_key":
                skill_keys += 1
        for s in t.get("samples", []):
            if "speed" in s:
                speeds.append(float(s["speed"]))
            samples_n += 1
    return {
        "delays": delays,
        "skill_keys": skill_keys,
        "avg_speed": sum(speeds) / len(speeds) if speeds else 0.0,
        "sprint_pct": (sum(1 for v in speeds if v > 200) / len(speeds) * 100) if speeds else 0.0,
        "samples": samples_n,
        "throws": throws,
        "duration": sum(t.get("duration", 0) for t in traces),
    }


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def build_prior(f):
    """特征→参数建议（每条含依据与方向；限幅护栏）。"""
    diff = []
    if len(f["delays"]) >= 3:
        med = statistics.median(f["delays"])
        # 主人持球→出手中位 < 0.5s = 节奏快于 AI 轮询 → 思考间隔对齐（只收紧）
        if med < 0.5:
            diff.append(("skill_think_interval", CURRENT["skill_think_interval"],
                         clamp(0.25, *GUARD["skill_think_interval"]),
                         f"主人持球→出手中位 {med}s < 0.5s：思考节拍收紧对齐"))
    # 技能键频次：主人每 10s 采样窗按键 ≥1 = 出手果断 → 阈值/能量门槛降
    keys_per_10s = f["skill_keys"] / max(f["duration"], 1.0) * 10.0
    if keys_per_10s >= 1.0:
        diff.append(("skill_use_threshold", CURRENT["skill_use_threshold"],
                     clamp(7.0, *GUARD["skill_use_threshold"]),
                     f"主人技能键 {keys_per_10s:.1f} 次/10s：出手果断，评分门槛下调"))
        diff.append(("skill_energy_min", CURRENT["skill_energy_min"],
                     clamp(5.0, *GUARD["skill_energy_min"]),
                     "同上：能量起放门槛下调（主人不为攒招干等）"))
    # 投球延迟方差小 = 决策稳定 → 不确定性折价降（更信当前评分）
    if len(f["delays"]) >= 5:
        stdev = statistics.pstdev(f["delays"])
        if stdev < 0.6:
            diff.append(("skill_uncertainty_discount", CURRENT["skill_uncertainty_discount"],
                         clamp(0.45, *GUARD["skill_uncertainty_discount"]),
                         f"主人出手延迟标准差 {stdev:.2f}s（稳定）：不确定性折价降"))
    # 观察项（无直接参数映射，写入报告不改值）
    observe = [
        f"均速 {f['avg_speed']:.0f} / 冲刺占比 {f['sprint_pct']:.0f}% → 走位呆板对照（P1）归 22-C S4 热图比对，不直接改 separation/avoid（单局过拟合风险）",
        f"出手 {f['throws']} 次 / 采样 {f['samples']} → 样本量{'充足' if f['throws'] >= 5 else '偏少（建议 ≥3 局或加局数）'}",
    ]
    return diff, observe


def main():
    pattern = sys.argv[1] if len(sys.argv) > 1 else None
    traces = load_traces(pattern)
    if not traces:
        print(f"⚠ 无轨迹文件（{USER_DIR}）——请先实机打局：F6 平台 --platform-human=0（详见 19号B/22-C 指引）")
        return 1
    f = extract(traces)
    diff, observe = build_prior(f)

    lines = []
    lines.append("# 22-C S3 先验转换报告（模仿学习·学主人打法）")
    lines.append("")
    lines.append(f"- 轨迹：{len(traces)} 局 / {f['duration']:.0f}s / 采样 {f['samples']} / 投球 {f['throws']} / 技能键 {f['skill_keys']}")
    lines.append(f"- 生成：tools/trace_prior.py（操球窗口 2026-09-30；基线=ai_profile.gd 现值 @ HEAD，22-A S6 参数未固化不掺入）")
    lines.append("")
    lines.append("## 参数 diff 建议（主人拍板后走 22-A 固化流程一次性替换）")
    lines.append("")
    lines.append("| 参数 | 现值 | 建议 | 依据（可解释映射） |")
    lines.append("|---|---|---|---|")
    if diff:
        for name, cur, sug, why in diff:
            lines.append(f"| {name} | {cur} | **{sug}** | {why} |")
    else:
        lines.append("| （无） | — | — | 样本量不足或主人打法与现参数已一致——建议加打 1~2 局再转 |")
    lines.append("")
    lines.append("## 观察项（不改值，对照验证用）")
    lines.append("")
    for o in observe:
        lines.append(f"- {o}")
    lines.append("")
    lines.append("## 固化纪律（22 档防范总则）")
    lines.append("- 建议≠替换：本表为主人拍板材料；替换一次性写入+旧值存档+全关门禁复验落新锚")
    lines.append("- 沙盒纪律：注入对照先在参数副本跑（22-A S2 同款），主线零改动")
    report = "\n".join(lines)
    out = "tools/trace_prior_report.md"
    io.open(out, "w", encoding="utf-8", newline="\n").write(report + "\n")
    print(report)
    print(f"\n→ 报告已落 {out}（交主人拍板；拍板后走 22-A S6 固化流程）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
