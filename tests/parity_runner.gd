## doc: 13 §6 引擎对拍
## 对拍运行器：与 tools/parity/gen_parity.ts 相同的种子清单与场景驱动，
## 逐行 diff TS 基准生成的期望日志；任何不一致 = 移植 bug 或公式漂移。
## 运行：godot --headless --path . -s res://tests/parity_runner.gd
## （期望日志由 npm run parity 先行生成）
extends SceneTree

const CONFIG_DIR: String = "res://resources/config/"


func _init() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	var tables := BattleSetup.load_tables(CONFIG_DIR)
	var cfg := BattleSetup.build_cfg(tables)
	var g: Dictionary = cfg.g
	var root := ProjectSettings.globalize_path("res://")
	var seeds_text := FileAccess.get_file_as_string(root.path_join("tools/parity/seeds.json"))
	if seeds_text.is_empty():
		print("PARITY ERROR: 读不到 tools/parity/seeds.json")
		return 1
	var seeds: Array = JSON.parse_string(seeds_text)
	if seeds == null or seeds.is_empty():
		print("PARITY ERROR: 种子清单为空")
		return 1
	var expected_dir := root.path_join("out/parity/expected")
	var failures := 0
	for seed_v in seeds:
		var seed := int(seed_v)
		var expected := FileAccess.get_file_as_string(expected_dir.path_join("seed_%d.log" % seed))
		if expected.is_empty():
			print("MISSING: seed_%d 期望日志缺失——先跑 npm run parity" % seed)
			failures += 1
			continue
		var actual := "\n".join(_build_lines(tables, cfg, g, seed))
		var expected_trimmed := expected.strip_edges()
		if actual != expected_trimmed:
			failures += 1
			print("PARITY FAIL: seed=%d" % seed)
			var a_lines := actual.split("\n")
			var e_lines := expected_trimmed.split("\n")
			for i in range(maxi(a_lines.size(), e_lines.size())):
				var a: String = a_lines[i] if i < a_lines.size() else "<缺失>"
				var e: String = e_lines[i] if i < e_lines.size() else "<缺失>"
				if a != e:
					print("  首个差异 行%d：" % (i + 1))
					print("    GD: %s" % a)
					print("    TS: %s" % e)
					break
	if failures == 0:
		print("PARITY OK: %d 个种子 × 3 场景 逐行一致" % seeds.size())
		return 0
	print("PARITY: %d/%d 个种子失败" % [failures, seeds.size()])
	return 1


## 场景驱动——与 tools/parity/gen_parity.ts 严格一致（勿单独改动任一侧）
func _build_lines(tables: Dictionary, cfg: Dictionary, g: Dictionary, seed: int) -> Array[String]:
	var lines: Array[String] = []
	lines.append("### seed=%d" % seed)

	var b1 := (
		Battle
		. new(
			cfg,
			[
				BattleSetup.make_pet_input(cfg, 1001, 12, 900, 1),
				BattleSetup.make_pet_input(cfg, 1002, 12, 900, 1),
				BattleSetup.make_pet_input(cfg, 1005, 12, 950, 1),
			],
			BattleSetup.group_inputs(tables, cfg, 4),
			seed
		)
	)
	var r1: Dictionary = b1.run()
	lines.append("[stage4] outcome=%s rounds=%d" % [r1.outcome, r1.rounds])
	for l in r1.log:
		lines.append(String(l))

	var b2 := (
		Battle
		. new(
			cfg,
			[
				BattleSetup.make_pet_input(cfg, 1006, 20, 1000, 2),
				BattleSetup.make_pet_input(cfg, 1002, 20, 950, 2),
				BattleSetup.make_pet_input(cfg, 1011, 20, 950, 2),
			],
			BattleSetup.group_inputs(tables, cfg, 6),
			seed
		)
	)
	var r2: Dictionary = b2.run()
	lines.append("[stage6] outcome=%s rounds=%d" % [r2.outcome, r2.rounds])
	for l in r2.log:
		lines.append(String(l))

	var b3 := (
		Battle
		. new(
			cfg,
			[
				BattleSetup.make_pet_input(cfg, 1009, 10, 900, 1),
				BattleSetup.make_pet_input(cfg, 1001, 10, 900, 1),
				BattleSetup.make_pet_input(cfg, 1005, 10, 950, 1),
			],
			BattleSetup.group_inputs(tables, cfg, 2),
			seed,
			{"capture": true}
		)
	)
	b3.try_capture(1, float(g.CAP_GOURD_JADE), float(g.CAP_Q3))
	if b3.outcome == "":
		b3.try_capture(1, float(g.CAP_GOURD_WOOD), float(g.CAP_Q1))
	var r3: Dictionary = b3.run()
	lines.append("[capture] outcome=%s rounds=%d" % [r3.outcome, r3.rounds])
	for l in r3.log:
		lines.append(String(l))
	return lines
