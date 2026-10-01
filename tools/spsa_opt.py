# -*- coding: utf-8 -*-
## 22-A 参数自搜索器（工单22，SPSA 简化版——Fishtest 同款思想）
## 用法:
##   python tools/spsa_opt.py baseline            # S3: 现值基线 5 种子（必须复现主线锚）
##   python tools/spsa_opt.py pilot [轮数=8]      # S4: SPSA 先导循环（断点续跑）
##   python tools/spsa_opt.py full [轮数=50]      # S4: 全量机时（同 pilot，轮数大）
##   python tools/spsa_opt.py duel [基线种子集]   # S5: 最优 vs 现值 对抗（3 新种子×2 侧）
## 红线一票否决: 卡死>0 / 接球率<50 / 比分0-0 → 该场 -1000
## 沙盒: 实验写 data/systems/spirit_ai/sandbox_profile.json（主线不携带，结束删除）
import json, os, re, subprocess, sys, time, math, random

GODOT = "E:/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
PROJECT = "E:/项目储存/决竞球battle-ball"
SCENE = "res://scenes/battle/battle_arena.tscn"
OVERRIDE = os.path.join(PROJECT, "data/systems/spirit_ai/sandbox_profile.json")
STATE_DIR = os.path.join(PROJECT, "sim_results", "spsa")
os.makedirs(STATE_DIR, exist_ok=True)

# ===== S1 参数空间（规范化 u∈[0,1] → 实值；基线=主线现值 2026-09-28）=====
PARAMS = [
    # name                          base   min    max
    ["skill_use_threshold",        10.0,   5.0,  20.0],
    ["skill_expected_future_score",25.0,  10.0,  45.0],
    ["skill_energy_min",           10.0,   5.0,  25.0],
    ["skill_mistake_chance",        0.15,  0.03,  0.30],
    ["skill_reserve_weight",        0.9,   0.5,   1.2],
    ["skill_uncertainty_discount",  0.6,   0.3,   0.9],
    ["skill_late_game_bonus",       1.5,   1.0,   2.0],
    ["skill_leading_penalty",       0.7,   0.3,   0.95],
]
A0, C0 = 0.06, 0.10   # SPSA 增益/扰动系数（u 空间）

WEIGHTS = {"catch": 0.30, "cover": 0.25, "switch": 0.15, "hit": 0.15, "miss": 0.15}
# 权重表（拟稿待主人签字）: 接球率30% + 技能覆盖率25% + 状态切换活跃(≤400归一)15%
#                     + 击中活跃(≤20归一)15% + 低失误15%；红线见文件头


def run_match(seed, half=80):
    out = os.path.join(STATE_DIR, f"match_s{seed}_{int(time.time())}.log")
    cmd = [GODOT, "--headless", "--fixed-fps", "60", "--sim", "--speed=6",
           f"--seed={seed}", f"--half={half}", SCENE]
    with open(out, "w", encoding="utf-8") as fh:
        subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, cwd=PROJECT, timeout=300)
    txt = io_open(out)
    def grab(pat, default=None, cast=float):
        mm = re.search(pat, txt)
        return cast(mm.group(1)) if mm else default
    a = grab(r"最终比分: (\d+) - (\d+)", None, int) if re.search(r"最终比分", txt) else None
    if a is None:
        os.remove(out)
        return None
    b = int(re.search(r"最终比分: \d+ - (\d+)", txt).group(1))
    catch = grab(r"同队接球率:\s*([\d.]+)%", 0.0)
    hit = grab(r"球击中球员: (\d+) 次", 0, int)
    stuck = grab(r"卡死触发: (\d+) 次", 0, int)
    switch = grab(r"状态切换: (\d+) 次", 0, int)
    cover = grab(r"覆盖率=([\d.]+)%", 0.0)
    miss = grab(r"失误率=([\d.]+)%", 100.0)
    os.remove(out)
    return {"score_a": a, "score_b": b, "catch": catch, "hit": hit,
            "stuck": stuck, "switch": switch, "cover_pct": cover, "miss": miss}


def io_open(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def score(m):
    if m is None:
        return -1000.0
    if m["stuck"] > 0 or m["catch"] < 50.0 or (m["score_a"] == 0 and m["score_b"] == 0):
        return -1000.0   # 红线一票否决
    s = (WEIGHTS["catch"] * m["catch"]
         + WEIGHTS["cover"] * m["cover_pct"]
         + WEIGHTS["switch"] * min(m["switch"], 400) / 4.0
         + WEIGHTS["hit"] * min(m["hit"], 20) * 5.0
         + WEIGHTS["miss"] * (100.0 - m["miss"]))
    return round(s, 2)


def write_override(u):
    obj = {}
    for i, spec in enumerate(PARAMS):
        val = spec[1] + u[i] * (spec[3] - spec[2])
        obj[spec[0]] = round(val, 4)
    with open(OVERRIDE, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    return obj


def clear_override():
    if os.path.exists(OVERRIDE):
        os.remove(OVERRIDE)


def u_to_params(u):
    return {spec[0]: round(spec[1] + u[i] * (spec[3] - spec[2]), 4)
            for i, spec in enumerate(PARAMS)}


def load_state():
    path = os.path.join(STATE_DIR, "state.json")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return {"round": 0, "u": [0.5] * len(PARAMS),
            "best": {"score": None, "u": None}, "history": []}


def save_state(st):
    with open(os.path.join(STATE_DIR, "state.json"), "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False, indent=1)


def cmd_baseline():
    print("== S3 基线校准（现值 5 种子，无沙盒覆盖）==")
    clear_override()
    rows = []
    for seed in (1, 2, 3, 4, 5):
        m = run_match(seed)
        s = score(m)
        rows.append(s)
        print(f"  seed{seed}: {json.dumps(m, ensure_ascii=False)} → 分 {s}")
    print(f"基线均分 {sum(rows)/len(rows):.2f}（主线锚逐位对照见日志归档）")


def cmd_pilot(rounds):
    st = load_state()
    total = int(rounds)
    print(f"== S4 SPSA 先导 {total} 轮（断点续跑: 当前第 {st['round']+1} 轮起）==")
    try:
        for k in range(total):
            r = st["round"] + 1
            c = C0 / (r ** 0.101)
            a = A0 / ((r + 10) ** 0.601)
            rng = random.Random(9000 + r)
            delta = [1.0 if rng.random() < 0.5 else -1.0 for _ in PARAMS]
            up = [min(1.0, max(0.0, st["u"][i] + c * delta[i])) for i in range(len(PARAMS))]
            dn = [min(1.0, max(0.0, st["u"][i] - c * delta[i])) for i in range(len(PARAMS))]
            seed_p, seed_n = 100 + r * 2, 100 + r * 2 + 1
            write_override(up)
            sp = score(run_match(seed_p))
            write_override(dn)
            sn = score(run_match(seed_n))
            g = [(sp - sn) / (2.0 * c * (delta[i] if delta[i] != 0 else 1.0)) for i in range(len(PARAMS))]
            st["u"] = [min(1.0, max(0.0, st["u"][i] + a * g[i])) for i in range(len(PARAMS))]
            avg = (sp + sn) / 2.0
            if st["best"]["score"] is None or avg > st["best"]["score"]:
                st["best"] = {"score": round(avg, 2), "u": list(st["u"]), "round": r}
            st["history"].append({"round": r, "sp": sp, "sn": sn, "avg": round(avg, 2)})
            st["round"] = r
            save_state(st)
            clear_override()
            print(f"  轮{r}: S+={sp} S-={sn} avg={avg:.2f} | best={st['best']['score']}")
    finally:
        clear_override()
        save_state(st)
    print("== 先导完成（断点续跑: spsa_opt.py full 50）==")
    print("最优 u =", json.dumps(st["best"], ensure_ascii=False))
    print("最优参数 =", json.dumps(u_to_params(st["best"]["u"]), ensure_ascii=False))


def cmd_duel(seeds):
    st = load_state()
    best_u = st["best"].get("u")
    if not best_u:
        print("无最优记录（先跑 pilot/full）")
        return
    seeds = [int(x) for x in seeds.split(",")] if seeds else [21, 22, 23]
    print(f"== S5 对抗验证: 最优 vs 现值，种子 {seeds} ==")
    rows = []
    for sd in seeds:
        write_override(best_u)
        mb = score(run_match(sd))
        clear_override()
        mc = score(run_match(sd))
        rows.append((mb, mc))
        print(f"  seed{sd}: 最优={mb} 现值={mc} Δ={mb-mc:+.2f}")
    db = sum(r[0] for r in rows) / len(rows)
    dc = sum(r[1] for r in rows) / len(rows)
    print(f"均分: 最优 {db:.2f} vs 现值 {dc:.2f}（Δ={db-dc:+.2f}；红线场已一票否决计分）")
    print("最优参数 =", json.dumps(u_to_params(best_u), ensure_ascii=False))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "baseline"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    if mode == "baseline":
        cmd_baseline()
    elif mode in ("pilot", "full"):
        cmd_pilot(arg if arg else ("8" if mode == "pilot" else "50"))
    elif mode == "duel":
        cmd_duel(arg)
    else:
        print("用法: baseline | pilot [n] | full [n] | duel [seeds]")


if __name__ == "__main__":
    main()
