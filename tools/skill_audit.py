#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
下一轮技能测试 · 验收流水线（批量技能矩阵工具）—— 平台窗口（就绪待命，正式开测等主人任务令）
按 17/18 复核表口径对现有技能做批量验收：每场 6 槽轮转装载 → headless 平台跑 →
日志解析 per-skill 出手（[Fx3D] 释放行）与效果应用（[TagEffect] 执行标签 _skill_id）→ 验收矩阵。

用法：
  python tools/skill_audit.py sample   # 小样自测（前 6 技一场，验证工具本身）
  python tools/skill_audit.py all      # 全量 18 技（3 场轮转）
产出：tools/skill_audit_matrix.md（验收矩阵）

判定口径：出手>0=AI 会用 ✅；效果应用/出手 ≥0.5=效果链健康；出手=0 ❌（查计价/gate/装载）。
"""
import json, io, os, re, subprocess, sys

GODOT = "E:/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
PROJECT = "E:/项目储存/决竞球battle-ball"
SKILLS = os.path.join(PROJECT, "data/spirits/skills.json")
AUDIT_LOADOUT = os.path.join(PROJECT, "data/systems/spirit_ai/_audit_loadout.json")
SCENE = "res://scenes/test3d/full_ai_platform.tscn"
HALF = 25.0  # 每场 25s 半场（出手窗口够用，跑批快）


def load_auditable():
    d = json.load(io.open(SKILLS, encoding="utf-8"))
    real = [s for s in d["skills"]
            if "e2e" not in s["id"] and "passive_test" not in s["id"] and s.get("type") != "passive"]
    return real


def spirit_id_for(skill_id, spirits):
    """技能归属元灵（spirit.skills 含该技的第一条）；找不到给梦幻。"""
    for sp in spirits:
        if skill_id in sp.get("skills", []):
            return str(sp.get("id"))
    return "spirit_menghuan"


def write_batch_loadout(skill_ids, all_skills, spirits):
    """6 槽轮转装载：每槽 1-2 技（skills.json 内存在的），skills 字段直配（绕开 test_spirits 依赖）。"""
    by_id = {s["id"]: s for s in all_skills}
    chars = ["char_001", "char_002", "char_003", "char_004", "char_005", "char_006"]
    loadouts = []
    for i, sid in enumerate(skill_ids[:6]):
        if sid not in by_id:
            continue
        loadouts.append({"slot": ("A%d" if i < 3 else "B%d") % (i % 3),
                         "character_id": chars[i],
                         "spirit_id": spirit_id_for(sid, spirits),
                         "skills": [sid]})
    cfg = {"schema_version": 2, "test_spirits": spirits, "loadouts": loadouts,
           "_说明": "skill_audit 批量验收临时装载（工具生成，跑完即删）"}
    with io.open(AUDIT_LOADOUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(cfg, f, ensure_ascii=False, indent="\t")
    return [l["skills"][0] for l in loadouts]


def run_match(seed):
    out = os.path.join(PROJECT, f"tools/_audit_match_s{seed}.log")
    cmd = [GODOT, "--headless", "--path", PROJECT, SCENE,
           "--platform-auto=1", f"--platform-seed={seed}", f"--half={HALF}",
           "--platform-loadout=res://data/systems/spirit_ai/_audit_loadout.json"]
    with open(out, "w", encoding="utf-8", errors="replace") as fh:
        subprocess.run(cmd, cwd=PROJECT, stdout=fh, stderr=subprocess.STDOUT, timeout=600)
    return io.open(out, encoding="utf-8", errors="replace").read()


def parse_stats(text, watched):
    """出手=[Fx3D] 释放行；效果=[TagEffect] 执行标签行 _skill_id。"""
    cast = {sid: 0 for sid in watched}
    effect = {sid: 0 for sid in watched}
    for m in re.finditer(r"\[Fx3D\] \S+ 释放 (\S+)", text):
        if m[1] in cast:
            cast[m[1]] += 1
    for m in re.finditer(r'\[TagEffect\] 执行标签: \S+ params=\{[^}]*"_skill_id": "([^"]+)"', text):
        if m[1] in effect:
            effect[m[1]] += 1
    return cast, effect


def audit_batch(skill_ids, seed):
    all_skills = json.load(io.open(SKILLS, encoding="utf-8"))["skills"]
    spirits = json.load(io.open(os.path.join(PROJECT, "data/spirits/spirits.json"), encoding="utf-8"))["spirits"]
    watched = write_batch_loadout(skill_ids, all_skills, spirits)
    text = run_match(seed)
    return parse_stats(text, watched)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "sample"
    real = load_auditable()
    ids = [s["id"] for s in real]
    names = {s["id"]: s.get("name", s["id"]) for s in real}
    batches = [ids[:6]] if mode == "sample" else [ids[i:i+6] for i in range(0, len(ids), 6)]
    print(f"== 技能验收矩阵（{mode}）：{sum(len(b) for b in batches)} 技 / {len(batches)} 场 ==")
    cast_total, effect_total = {}, {}
    for bi, batch in enumerate(batches):
        c, e = audit_batch(batch, seed=10 + bi)
        for k in c:
            cast_total[k] = cast_total.get(k, 0) + c[k]
            effect_total[k] = effect_total.get(k, 0) + e[k]
        print(f"  批{bi+1} 完成（seed={10+bi}）")
    lines = ["# 技能验收矩阵（下一轮技能测试 · 流水线产出）", "",
             "| 技能 | 名称 | AI出手 | 效果应用 | 判定 |", "|---|---|---|---|---|"]
    ok = 0
    for sid in ids:
        if sid not in cast_total:
            continue  # 未入本轮批次
        c, e = cast_total[sid], effect_total[sid]
        verdict = "✅ 会用+效果落地" if c > 0 and e >= c * 0.5 else ("⚠ 会用但效果存疑" if c > 0 else "❌ AI 不出手（查计价/gate）")
        ok += 1 if c > 0 and e >= c * 0.5 else 0
        lines.append(f"| {sid} | {names[sid]} | {c} | {e} | {verdict} |")
    lines += ["", f"**全绿率：{ok}/{len(cast_total)}**"]
    report = "\n".join(lines)
    io.open(os.path.join(PROJECT, "tools/skill_audit_matrix.md"), "w", encoding="utf-8", newline="\n").write(report)
    if os.path.exists(AUDIT_LOADOUT):
        os.remove(AUDIT_LOADOUT)
    print(report)
    print("\n已落盘 tools/skill_audit_matrix.md")


if __name__ == "__main__":
    main()
