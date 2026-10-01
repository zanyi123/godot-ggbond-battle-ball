#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
22-A 参数自搜索器（简化版 SPSA，Fishtest 同款思想）—— 平台窗口（代集成工装域），主人 0928-2/0930 令
工单22 §22-A：S1 打分函数 / S2 参数副本沙盒 / S3 基线校准 / S4 SPSA 循环（断点续跑）

用法：
  python tools/spsa_tuner.py baseline   # S3：现值参数 5 种子 ×2（确定性核验+基线分）
  python tools/spsa_tuner.py pilot      # S4：SPSA 10 轮试点（20 场，断点续跑）
  python tools/spsa_tuner.py run --rounds 50   # 完整 SPSA（断点续跑）

防范总则（工单22）：沙盒副本（主线 profile/switches 零改动，固化=主人拍板后另行处理）；
红线一票否决（卡死>0 / 接球率<50% / 出手=0 → 该组合作废记 0 分）。
权重表=草案（待主人签字，签字前产物仅分析用不固化）。
"""
import json, os, re, subprocess, sys, time, random, io

GODOT = "E:/项目储存/pvz-project/pvz-godot/tools/Godot_v4.6.2-stable_win64_console.exe"
PROJECT = "E:/项目储存/决竞球battle-ball"
SCENE = "res://scenes/battle/battle_arena.tscn"
SANDBOX = os.path.join(PROJECT, "data/systems/spirit_ai/sandbox_profile.json")
CKPT = os.path.join(PROJECT, "tools/spsa_state.json")
CSV = os.path.join(PROJECT, "tools/spsa_log.csv")
SEEDS = [1, 2, 3, 4, 5, 6, 7, 8]  # 0930-1 主人批：扩到 8 种子（训练轮换池）
HALF = 80.0

# ===== S1a 参数向量（默认值=当前主线；bounds 防越界；sigma=SPSA 扰动步长）=====
PARAMS = {
	"skill_use_threshold":          {"d": 10.0, "min": 5.0,  "max": 25.0, "sigma": 2.0},
	"skill_expected_future_score":  {"d": 25.0, "min": 10.0, "max": 60.0, "sigma": 5.0},
	"skill_uncertainty_discount":   {"d": 0.6,  "min": 0.2,  "max": 0.9,  "sigma": 0.08},
	"skill_think_interval":         {"d": 0.5,  "min": 0.3,  "max": 1.0,  "sigma": 0.08},
	"skill_late_game_bonus":        {"d": 1.5,  "min": 1.0,  "max": 2.5,  "sigma": 0.15},
	"skill_losing_bonus":           {"d": 1.3,  "min": 1.0,  "max": 2.0,  "sigma": 0.10},
	"skill_leading_penalty":        {"d": 0.7,  "min": 0.3,  "max": 1.0,  "sigma": 0.08},
	"skill_element_counter_bonus":  {"d": 1.3,  "min": 1.0,  "max": 2.0,  "sigma": 0.10},
	"skill_element_counter_penalty":{"d": 0.7,  "min": 0.4,  "max": 1.0,  "sigma": 0.06},
	"skill_energy_min":             {"d": 10.0, "min": 5.0,  "max": 20.0, "sigma": 2.0},
}

# ===== S1b 打分权重表（草案 v1，待主人签字；签字前产物仅分析用）=====
W = {
	"coverage": 0.30,   # 技能覆盖率 0-100%（10技能池），目标 100
	"pass_rate": 0.25,  # 同队接球率：50→0 分线性到 100→满（<50 红线否决）
	"ball_ratio": 0.15, # BALL 技出手占比（4 球技池中出手过的比例）——P2 指向
	"switch_band": 0.15,# 状态切换数健康带 [30,400] 中点 215，偏离衰减（过低呆/过高抖）
	"goals": 0.15,      # 进球总数（≤8 封顶）——对局活性
}
RED = {"stuck": 0, "pass_rate": 50.0}  # 红线：卡死>0 / 接球率<50% → 否决记 0 分


def run_sim(seed: int) -> dict:
	"""跑一场 sim（文件重定向纪律），返回指标 dict。"""
	out = os.path.join(PROJECT, f"tools/_spsa_match_s{seed}.log")
	cmd = [GODOT, "--headless", "--fixed-fps", "60", "--sim", "--speed=6",
		   f"--seed={seed}", f"--half={HALF}", SCENE]
	with open(out, "w", encoding="utf-8", errors="replace") as fh:
		proc = subprocess.run(cmd, cwd=PROJECT, stdout=fh, stderr=subprocess.STDOUT, timeout=600)
	text = io.open(out, encoding="utf-8", errors="replace").read()
	# 0928-7 批准口径：headless 随机闪退（exit≠0 或无终局行）自动复跑一次
	if proc.returncode != 0 or "最终比分" not in text:
		print(f"    [0928-7] seed{seed} 闪退(exit={proc.returncode})→自动复跑一次")
		with open(out, "w", encoding="utf-8", errors="replace") as fh:
			proc = subprocess.run(cmd, cwd=PROJECT, stdout=fh, stderr=subprocess.STDOUT, timeout=600)
		text = io.open(out, encoding="utf-8", errors="replace").read()
	m = {}
	line = re.search(r"最终比分: (\d+) - (\d+)", text)
	if line:
		m["goals_a"], m["goals_b"] = int(line[1]), int(line[2])
	summ = re.search(r"SUMMARY 出手=(\d+)/(\d+) 覆盖率=([0-9.]+)% BALL=(\d+)/\d+ PLAYER=(\d+)/\d+ FIELD=(\d+)/\d+", text)
	if summ:
		m["cast"], m["pool"] = int(summ[1]), int(summ[2])
		m["coverage"] = float(summ[3])
		m["ball_cast"] = int(summ[4])
	cr = re.search(r"同队接球率[:：]?\s*([0-9.]+)%", text)
	m["pass_rate"] = float(cr[1]) if cr else 0.0
	st = re.search(r"卡死触发:\s*(\d+)", text)
	m["stuck"] = int(st[1]) if st else 0
	sc = re.search(r"状态切换:\s*(\d+)", text)
	m["switches"] = int(sc[1]) if sc else 0
	m["exit"] = proc.returncode
	return m


def score(m: dict) -> float:
	"""S1b 健康分 0-100（红线一票否决）。"""
	if m.get("stuck", 1) > RED["stuck"]:
		return 0.0
	if m.get("pass_rate", 0) < RED["pass_rate"]:
		return 0.0
	if m.get("cast", 0) == 0:
		return 0.0
	s = 0.0
	s += W["coverage"] * min(m.get("coverage", 0.0), 100.0)          # 30 满分
	s += W["pass_rate"] * max(0.0, min(1.0, (m.get("pass_rate", 0.0) - 50.0) / 50.0)) * 100
	pool = max(m.get("pool", 10) // 5, 1)  # 球技池≈总池 2/5 换算（4/10）
	s += W["ball_ratio"] * min(m.get("ball_cast", 0) / max(pool, 1), 1.0) * 100
	sw = m.get("switches", 0)
	s += W["switch_band"] * max(0.0, 1.0 - abs(sw - 215) / 185.0) * 100
	goals = m.get("goals_a", 0) + m.get("goals_b", 0)
	s += W["goals"] * min(goals, 8) / 8 * 100
	return round(s, 2)


def eval_seed(seed: int) -> tuple:
	m = run_sim(seed)
	return score(m), m


def write_sandbox(theta: dict) -> None:
	with open(SANDBOX, "w", encoding="utf-8", newline="\n") as f:
		json.dump(theta, f, ensure_ascii=False, indent="\t")


def clear_sandbox() -> None:
	if os.path.exists(SANDBOX):
		os.remove(SANDBOX)


def cmd_baseline() -> None:
	"""S3：现值参数（默认值，无沙盒文件）5 种子 ×2——确定性核验+基线分。"""
	clear_sandbox()
	print("== S3 基线校准：默认参数 5 种子 ×2 ==")
	runs = []
	for rep in range(2):
		scores, metrics = [], []
		for seed in SEEDS:
			sc, m = eval_seed(seed)
			scores.append(sc)
			metrics.append(m)
			print(f"  rep{rep+1} seed{seed}: score={sc} 覆盖{m.get('coverage')}% 接球{m.get('pass_rate')}% "
				  f"切换{m.get('switches')} 卡死{m.get('stuck')} 比分{m.get('goals_a')}-{m.get('goals_b')}")
		runs.append((scores, metrics))
	det = all(runs[0][0][i] == runs[1][0][i] for i in range(len(SEEDS)))
	base = sum(runs[0][0]) / len(runs[0][0])
	print(f"确定性核验（两轮逐种子同分）: {'✅ 通过' if det else '❌ 失败（存在非确定性，实验无效）'}")
	print(f"基线分（第1轮均值）: {base}")
	json.dump({"baseline_score": base, "deterministic": det,
			   "runs": [{"scores": r[0], "metrics": r[1]} for r in runs]},
			  io.open(os.path.join(PROJECT, "tools/spsa_baseline.json"), "w", encoding="utf-8"),
			  ensure_ascii=False, indent=1)
	print("已落盘 tools/spsa_baseline.json")


def cmd_run(rounds: int) -> None:
	"""S4：SPSA 主循环（断点续跑；每轮 2 场）。"""
	state = {"round": 0, "theta": {k: v["d"] for k, v in PARAMS.items()},
			 "best": {"score": -1.0, "theta": None}, "rng": 20260930}
	if os.path.exists(CKPT):
		state = json.load(io.open(CKPT, encoding="utf-8"))
		print(f"断点续跑：从第 {state['round']+1} 轮继续")
	if not os.path.exists(CSV):
		io.open(CSV, "w", encoding="utf-8").write(
			"round,seed_pos,seed_neg,score_pos,score_neg,mean,," + ",".join(PARAMS.keys()) + "\n")
	rng = random.Random(state["rng"])
	start = state["round"]
	for k in range(start, rounds):
		ck = 0.15 / ((k + 1) ** 0.101)      # SPSA 扰动幅（相对参数量纲 σ 缩放）
		ak = 2.0 / ((k + 11) ** 0.602)      # 步长
		delta = {name: (1 if rng.random() < 0.5 else -1) for name in PARAMS}
		theta_p, theta_m = {}, {}
		for name, spec in PARAMS.items():
			d = ck * spec["sigma"] * delta[name]
			theta_p[name] = min(spec["max"], max(spec["min"], state["theta"][name] + d))
			theta_m[name] = min(spec["max"], max(spec["min"], state["theta"][name] - d))
		sp = sn = 0.0
		s1 = SEEDS[k % len(SEEDS)]
		s2 = SEEDS[(k + 1) % len(SEEDS)]
		write_sandbox(theta_p)
		sp = (eval_seed(s1)[0] + eval_seed(s2)[0]) / 2
		write_sandbox(theta_m)
		sn = (eval_seed(s1)[0] + eval_seed(s2)[0]) / 2
		for name in PARAMS:
			g = (sp - sn) / (2 * ck * PARAMS[name]["sigma"] * delta[name])
			v = state["theta"][name] + ak * g * PARAMS[name]["sigma"]
			state["theta"][name] = min(PARAMS[name]["max"], max(PARAMS[name]["min"], v))
		mean = (sp + sn) / 2
		if mean > state["best"]["score"]:
			state["best"] = {"score": mean, "theta": dict(state["theta"])}
		state["round"] = k + 1
		state["rng"] = rng.randrange(1 << 30)
		with io.open(CSV, "a", encoding="utf-8") as f:
			f.write(f"{k+1},{s1},{s2},{sp},{sn},{mean},," + ",".join(
				f"{state['theta'][n]:.3f}" for n in PARAMS) + "\n")
		json.dump(state, io.open(CKPT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
		print(f"[轮 {k+1}/{rounds}] S+={sp} S-={sn} 均值={mean} | 最佳={state['best']['score']}")
	clear_sandbox()
	print(f"\nSPSA 完成：最佳均值={state['best']['score']}")
	print("最佳参数（沙盒实验产物，固化待主人拍板）:")
	print(json.dumps(state["best"]["theta"], ensure_ascii=False, indent=1))


if __name__ == "__main__":
	mode = sys.argv[1] if len(sys.argv) > 1 else "baseline"
	if mode == "baseline":
		cmd_baseline()
	elif mode == "pilot":
		cmd_run(10)
	elif mode == "run":
		r = int(sys.argv[sys.argv.index("--rounds") + 1]) if "--rounds" in sys.argv else 50
		cmd_run(r)
	else:
		print("用法: baseline | pilot | run --rounds N")
