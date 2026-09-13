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


## 事件摘要（docs/10 §8.1）：与 tools/parity/gen_parity.ts evDigest 同格式
func _ev_digest(e: Dictionary) -> String:
	match String(e.t):
		"start":
			var parts: Array[String] = []
			for x in e.units:
				parts.append(
					"%d:%d:%s:%d:%d" % [int(x.u), int(x.s), String(x.n), int(x.hp), int(x.el)]
				)
			return "[ev] start units=" + ";".join(parts)
		"cast":
			var tg: Array = []
			for u0 in e.tg:
				tg.append(str(int(u0)))
			return (
				"[ev] cast r=%d u=%d s=%s tg=%s" % [int(e.r), int(e.u), String(e.s), "|".join(tg)]
			)
		"hit":
			return "[ev] hit u=%d d=%d hp=%d c=%d" % [int(e.u), int(e.d), int(e.hp), int(e.c)]
		"heal":
			return "[ev] heal u=%d a=%d hp=%d" % [int(e.u), int(e.a), int(e.hp)]
		"shield":
			return "[ev] shield u=%d a=%d" % [int(e.u), int(e.a)]
	return _ev_digest_more(e)


func _ev_digest_more(e: Dictionary) -> String:
	match String(e.t):
		"buff":
			return "[ev] buff u=%d b=%s st=%d" % [int(e.u), String(e.b), int(e.st)]
		"death":
			return "[ev] death u=%d" % int(e.u)
		"sub":
			return "[ev] sub u=%d n=%s s=%d" % [int(e.u), String(e.n), int(e.s)]
		"cap":
			return "[ev] cap u=%d tu=%d rt=%d ok=%d" % [int(e.u), int(e.tu), int(e.rt), int(e.ok)]
		"end":
			return "[ev] end o=%s r=%d" % [String(e.o), int(e.r)]
	return _ev_digest_rest(e)


func _ev_digest_rest(e: Dictionary) -> String:
	match String(e.t):
		"round":
			return "[ev] round r=%d" % int(e.r)
		"dodge":
			return "[ev] dodge u=%d" % int(e.u)
	return "[ev] %s" % String(e.t)


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
		print("PARITY OK: %d 个种子 × 9 场景 逐行一致" % seeds.size())
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
	for l0 in r1.events:
		lines.append(_ev_digest(l0))

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
	for l0 in r2.events:
		lines.append(_ev_digest(l0))

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
	for l0 in r3.events:
		lines.append(_ev_digest(l0))

	var ec := BattleSetup.build_equip_config(tables)
	var drop := func(
		seq: int, drop_id: int, count: int, level: int, luck: float, pity: Dictionary
	) -> Dictionary:
		return (
			EquipDropResolver
			. resolve_settlement(
				{
					"rootSeed": seed,
					"settlementSeq": seq,
					"dropId": drop_id,
					"dropCount": count,
					"monsterLevel": level,
					"luckValue": luck,
					"pityState": pity,
				},
				ec,
				g
			)
		)

	for l in drop.call(1001, 1, 2, 12, 0.0, EquipDropResolver.empty_pity_state()).canonicalLog:
		lines.append(String(l))

	var pity14 := {"schemaVersion": 1, "counters": {"2": 14}}
	var loot_b: Dictionary = drop.call(1002, 2, 3, 20, 100.0, pity14)
	for l in loot_b.canonicalLog:
		lines.append(String(l))
	for l in drop.call(1003, 2, 3, 20, 100.0, loot_b.pityAfter).canonicalLog:
		lines.append(String(l))

	var c: Dictionary = drop.call(1004, 3, 1, 30, 250.0, EquipDropResolver.empty_pity_state())
	for l in c.canonicalLog:
		lines.append(String(l))
	var view: Dictionary = EquipDropResolver.resolve_identification(c.items[0], ec, g)
	var affixes: Array = view.affixes
	var first_id := -1
	var first_micro := -1
	if not affixes.is_empty():
		first_id = int(affixes[0].affixId)
		first_micro = int(affixes[0].valueMicro)
	lines.append(
		(
			"[loot_ident] instanceId=%s mainValueMicro=%d affixCount=%d firstAffix=%d firstMicro=%d"
			% [
				String(c.items[0].instanceId),
				int(view.mainValueMicro),
				affixes.size(),
				first_id,
				first_micro
			]
		)
	)

	var crops := {}
	crops[1] = {"cropId": 1, "growMin": 30, "yieldN": 6, "outputItemId": 101, "outputCount": 6}
	crops[5] = {"cropId": 5, "growMin": 240, "yieldN": 3, "outputItemId": 105, "outputCount": 3}
	var seasons := {}
	seasons[0] = {"farmMult": 1.2}
	seasons[1] = {"farmMult": 1.0}
	seasons[2] = {"farmMult": 1.3}
	seasons[3] = {"farmMult": 0.5}
	var vconfig := {
		"crops": crops,
		"seasons": seasons,
		"categoryOf": {101: 3, 105: 2},
		"storageRules": {2: 150, 3: 100},
		"g":
		{
			"SEASON_EPOCH_UTC_SEC": 0,
			"OFFLINE_CAP_BASE_SEC": 43200,
			"STORAGE_DECAY_PCT": 0.1,
			"STORAGE_DECAY_PERIOD_SEC": 86400,
		},
	}
	var farm_scenario := func(fields: Array, cursor: int, now: int, inv: Array) -> void:
		var r: Dictionary = VillageProduction.settle_crops(fields, cursor, now, inv, vconfig)
		lines.append(
			(
				"[farm] cursor=%d now=%d cappedBy=%d outputs=%d fields=%d"
				% [cursor, now, int(r.cappedBy), r.outputs.size(), r.nextFields.size()]
			)
		)
		for o in r.outputs:
			lines.append(
				(
					"[farm_out] item=%d amount=%d season=%d"
					% [int(o.itemId), int(o.amount), int(o.season)]
				)
			)
		for s in r.inventory:
			lines.append("[farm_inv] item=%d amount=%d" % [int(s.itemId), int(s.amount)])

	(
		farm_scenario
		. call(
			[
				{"slotId": 1, "cropId": 1, "startedAtUtcSec": 430000},
				{"slotId": 2, "cropId": 5, "startedAtUtcSec": 100},
			],
			430000,
			432200,
			[]
		)
	)
	farm_scenario.call(
		[{"slotId": 1, "cropId": 1, "startedAtUtcSec": 0}],
		0,
		90000,
		[{"itemId": 101, "amount": 120}]
	)

	# 场景6：建筑效果（Phase B）——与 tools/parity/gen_parity.ts 同字面量
	var build_rows: Array = [
		{"buildingId": 1, "maxLevel": 10, "effectKind": 1, "effectBase": 0, "effectStep": 1},
		{"buildingId": 4, "maxLevel": 6, "effectKind": 1, "effectBase": 3, "effectStep": 1},
		{"buildingId": 5, "maxLevel": 6, "effectKind": 1, "effectBase": 1, "effectStep": 1},
		{"buildingId": 7, "maxLevel": 5, "effectKind": 3, "effectBase": 1, "effectStep": 0.5},
		{"buildingId": 9, "maxLevel": 6, "effectKind": 2, "effectBase": 1, "effectStep": 0.5},
		{"buildingId": 12, "maxLevel": 5, "effectKind": 1, "effectBase": 12, "effectStep": 12},
	]
	var build_state: Array = [
		{"buildingId": 4, "level": 2},
		{"buildingId": 5, "level": 1},
		{"buildingId": 7, "level": 3},
		{"buildingId": 9, "level": 2},
		{"buildingId": 12, "level": 1},
		{"buildingId": 1, "level": 2},
	]
	var build_g := {"OFFLINE_CAP_BASE_SEC": 43200, "OFFLINE_CAP_TOTEM_SEC": 86400}
	(
		lines
		. append(
			(
				"[build] farmSlots=%d mineSlots=%d forgeCap=%d warehouseMult=%.2f totemCap=%d hallGate=%d"
				% [
					BuildingEffects.field_slots(build_state, build_rows),
					BuildingEffects.mine_slots(build_state, build_rows),
					BuildingEffects.queue_cap(build_state, BuildingEffects.FORGE, build_rows),
					BuildingEffects.storage_cap_mult(build_state, build_rows),
					BuildingEffects.offline_cap_sec(build_state, build_rows, build_g),
					BuildingEffects.upgrade_cap(build_state, BuildingEffects.FARM, build_rows),
				]
			)
		)
	)

	# 场景7：配方生产（Phase B）
	var recipe_map := {
		4:
		{
			"recipeId": 4,
			"station": 1,
			"inputs": "201:2;206:2",
			"outputItemId": 206,
			"outputCount": 1,
			"durationMin": 30
		},
	}
	var recipe_of := func(recipe_id: int) -> Dictionary: return recipe_map.get(recipe_id, {})
	var craft_category := {201: 1, 206: 5}
	var craft_rules := {1: 200, 5: 50}
	var inv0: Array = [{"itemId": 201, "amount": 5}, {"itemId": 206, "amount": 2}]
	var inv_str := func(inv: Array) -> String:
		if inv.is_empty():
			return "-"
		var parts: Array[String] = []
		for s0 in inv:
			parts.append("%d:%d" % [int(s0.itemId), int(s0.amount)])
		return ";".join(parts)
	var s7: Dictionary = RecipeCraft.start_craft([], 4, "201:2;206:2", 1000, inv0, 2)
	lines.append(
		(
			"[recipe_start] error=%s jobs=%d inv=%s"
			% [String(s7.error), s7.jobs.size(), inv_str.call(s7.inventory)]
		)
	)
	var half7: Dictionary = RecipeCraft.settle_crafts(
		s7.jobs, 1000 + 29 * 60, s7.inventory, recipe_of, craft_category, craft_rules, 1.0
	)
	lines.append(
		"[recipe_settle_half] jobs=%d outputs=%d" % [half7.nextJobs.size(), half7.outputs.size()]
	)
	var done7: Dictionary = RecipeCraft.settle_crafts(
		s7.jobs, 1000 + 30 * 60, s7.inventory, recipe_of, craft_category, craft_rules, 2.0
	)
	lines.append(
		(
			"[recipe_settle_done] jobs=%d outputs=%d inv=%s"
			% [done7.nextJobs.size(), done7.outputs.size(), inv_str.call(done7.inventory)]
		)
	)

	# 场景8：矿场结算（Phase B）
	var mine_config := {
		"mines":
		{
			1: {"mineId": 1, "ironRate": 10, "crystalRate": 2, "refinedRate": 1, "spiritRate": 1},
			2: {"mineId": 2, "ironRate": 6, "crystalRate": 3, "refinedRate": 0, "spiritRate": 2},
		},
		"seasons":
		{0: {"mineMult": 1.2}, 1: {"mineMult": 1.0}, 2: {"mineMult": 1.3}, 3: {"mineMult": 0.5}},
		"categoryOf": {201: 1, 202: 1, 203: 1},
		"storageRules": {1: 200},
		"g": {"SEASON_EPOCH_UTC_SEC": 0, "OFFLINE_CAP_BASE_SEC": 43200},
	}
	var mine_jobs: Array = [
		{"slotId": 1, "mineId": 1, "startedAtUtcSec": 430000, "assignedPetInstanceIds": []},
		{"slotId": 2, "mineId": 2, "startedAtUtcSec": 430000, "assignedPetInstanceIds": []},
	]
	var r8: Dictionary = MineProduction.settle_mines(
		mine_jobs,
		430000,
		444400,
		{"beastShell": 5, "spiritCrystal": 50, "totemEmblem": 0},
		[],
		mine_config
	)
	(
		lines
		. append(
			(
				"[mine] cursor=430000 now=444400 outputs=%d wallet=spirit:%d,beast:%d,totem:%d inv=%s"
				% [
					r8.outputs.size(),
					int(r8.wallet.spiritCrystal),
					int(r8.wallet.beastShell),
					int(r8.wallet.totemEmblem),
					inv_str.call(r8.inventory),
				]
			)
		)
	)
	for o8 in r8.outputs:
		lines.append("[mine_out] item=%d amount=%d" % [int(o8.itemId), int(o8.amount)])

	# 场景9：兽潮错过补结算（Phase B）
	var team9: Array = [
		BattleSetup.make_pet_input(cfg, 1001, 12, 900, 1),
		BattleSetup.make_pet_input(cfg, 1002, 12, 900, 1),
		BattleSetup.make_pet_input(cfg, 1005, 12, 950, 1),
	]
	var t9: Dictionary = BeastTide.settle_missed(
		864000000, 864172800, 28800, seed, team9, tables, cfg, g
	)
	lines.append(
		(
			"[beast] cursor=864000000 now=864172800 tz=28800 waves=%d settled=%d"
			% [t9.waves.size(), int(t9.settledCount)]
		)
	)
	for w9 in t9.waves:
		lines.append(
			(
				"[beast_wave] utc=%d outcome=%s rounds=%d"
				% [int(w9.waveUtcSec), String(w9.outcome), int(w9.rounds)]
			)
		)
	return lines
