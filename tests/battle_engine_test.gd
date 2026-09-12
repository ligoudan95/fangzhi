## doc: 07 §5（确定性验收）/ 12 §V-501（冒烟）
## TS 基准 tests/battle.test.ts 的断言口径平移。
extends GdUnitTestSuite

var _tables: Dictionary = {}
var _cfg: Dictionary = {}


func before_test() -> void:
	if _tables.is_empty():
		_tables = BattleSetup.load_tables("res://resources/config/")
		_cfg = BattleSetup.build_cfg(_tables)


func _team() -> Array:
	return [
		BattleSetup.make_pet_input(_cfg, 1001, 12, 900, 1),
		BattleSetup.make_pet_input(_cfg, 1002, 12, 900, 1),
		BattleSetup.make_pet_input(_cfg, 1005, 12, 950, 1),
	]


## 确定性：同种子同输入 → 逐行一致的战斗日志
func test_determinism_same_seed() -> void:
	var a: Dictionary = (
		Battle.new(_cfg, _team(), BattleSetup.group_inputs(_tables, _cfg, 4), 42).run()
	)
	var b: Dictionary = (
		Battle.new(_cfg, _team(), BattleSetup.group_inputs(_tables, _cfg, 4), 42).run()
	)
	assert_array(a.log).is_equal(b.log)
	assert_int(a.rounds).is_equal(b.rounds)
	assert_str(a.outcome).is_equal(b.outcome)


## 引擎可跑完一场 Boss 战（关卡6 域主藤皇）
func test_boss_battle_completes() -> void:
	var boss_team := [
		BattleSetup.make_pet_input(_cfg, 1006, 20, 1000, 2),
		BattleSetup.make_pet_input(_cfg, 1002, 20, 950, 2),
		BattleSetup.make_pet_input(_cfg, 1011, 20, 950, 2),
	]
	var r: Dictionary = (
		Battle.new(_cfg, boss_team, BattleSetup.group_inputs(_tables, _cfg, 6), 7).run()
	)
	assert_bool(["victory", "defeat", "timeout"].has(r.outcome)).is_true()
	assert_int(r.rounds).is_greater_equal(1)
	assert_int(r.rounds).is_less_equal(30)


## 捕捉模式：战斗可以以 captured 结束（种子 1..50）
func test_capture_mode_completes() -> void:
	for seed in range(1, 51):
		var t := [
			BattleSetup.make_pet_input(_cfg, 1009, 10, 900, 1),
			BattleSetup.make_pet_input(_cfg, 1001, 10, 900, 1),
			BattleSetup.make_pet_input(_cfg, 1005, 10, 950, 1),
		]
		var b := Battle.new(
			_cfg, t, BattleSetup.group_inputs(_tables, _cfg, 2), seed, {"capture": true}
		)
		var target: Dictionary = {}
		for u in b.units:
			if int(u.side) == 1:
				target = u
				break
		var r: Dictionary = b.run()
		assert_str(r.outcome).is_not_empty()
		assert_int(r.log.size()).is_greater(0)
		if r.outcome == "captured":
			assert_int(r.capturedPetId).is_equal(int(target.petId))


## 捕捉模式：低血目标消耗我方行动准备，在敌方行动后结算
func test_capture_mode_uses_action_and_settles_after_enemy_turn() -> void:
	var capture_cfg: Dictionary = _cfg.duplicate(true)
	capture_cfg.g.ROUND_CAP = 1
	capture_cfg.g.CAP_GOURD_JADE = 1.0
	capture_cfg.g.CAP_Q1 = 1.0
	capture_cfg.g.CAP_HP_LO = 1.0
	capture_cfg.g.CAP_ST_CTRL = 1.0
	capture_cfg.g.CAP_ST_DEBUFF = 1.0
	var battle := Battle.new(
		capture_cfg,
		[BattleSetup.make_pet_input(capture_cfg, 1001, 1, 900, 0)],
		[
			BattleSetup.make_pet_input(
				capture_cfg, 1003, 1, 900, 0, {"captureable": true, "strategy": "focus_weak"}
			)
		],
		7,
		{"capture": true}
	)
	var actor: Dictionary = battle.units[0]
	var target: Dictionary = battle.units[1]
	actor.stats.spd = 1000
	target.stats.spd = 1
	target.hp = floori(float(target.stats.hp) * 0.19)

	var result: Dictionary = battle.run()
	var prepare_index := _find_log(result.log, "%s 准备收妖" % String(actor.name))
	var enemy_index := _find_log(result.log, "[敌]%s 施放" % String(target.name))
	var settle_index := _find_log(result.log, "%s 祭出祖灵葫芦" % String(actor.name))
	assert_str(result.outcome).is_equal("captured")
	assert_int(result.capturedPetId).is_equal(int(target.petId))
	assert_bool(prepare_index >= 0 and prepare_index < enemy_index).is_true()
	assert_bool(enemy_index < settle_index).is_true()
	assert_int(_find_log(result.log, "%s 施放" % String(actor.name))).is_equal(-1)


## 多段攻击：目标倒下后后续 hit 转投剩余最低血量敌人
func test_multi_hit_retargers_after_target_dies() -> void:
	var battle_cfg: Dictionary = _cfg.duplicate(true)
	battle_cfg.g.ROUND_CAP = 1
	battle_cfg.g.HIT_BASE = 1.0
	battle_cfg.g.CRIT_BASE = 0.0
	battle_cfg.g.FLOAT_MIN = 1.0
	battle_cfg.g.FLOAT_MAX = 1.0
	battle_cfg.skills[3].cd = 0
	battle_cfg.skills[3].learnLv = 1
	var attacker_input: Dictionary = BattleSetup.make_pet_input(
		battle_cfg, 1001, 1, 900, 0, {"strategy": "focus_weak"}
	)
	attacker_input.skillIds = [3]
	var battle := (
		Battle
		. new(
			battle_cfg,
			[attacker_input],
			[
				BattleSetup.make_pet_input(battle_cfg, 1003, 1, 900, 0),
				BattleSetup.make_pet_input(battle_cfg, 1004, 1, 900, 0),
			],
			11
		)
	)
	var attacker: Dictionary = battle.units[0]
	var first: Dictionary = battle.units[1]
	var second: Dictionary = battle.units[2]
	attacker.stats.atk = 10000
	attacker.stats.spd = 1000
	first.stats.spd = 1
	second.stats.spd = 1
	first.hp = 1
	second.hp = 100

	var result: Dictionary = battle.run()
	var hit_lines: Array[String] = []
	for line in result.log:
		if String(line).contains("受到"):
			hit_lines.append(String(line))
	assert_bool(hit_lines[0].contains(String(first.name))).is_true()
	assert_bool(hit_lines[1].contains(String(second.name))).is_true()


## 嘲讽：不动如山强制敌方攻击施法者并持续两回合
func test_taunt_forces_target_and_tracks_duration() -> void:
	var battle_cfg: Dictionary = _cfg.duplicate(true)
	battle_cfg.g.ROUND_CAP = 1
	battle_cfg.g.HIT_BASE = 1.0
	battle_cfg.g.CRIT_BASE = 0.0
	battle_cfg.g.FLOAT_MIN = 1.0
	battle_cfg.g.FLOAT_MAX = 1.0
	var battle := (
		Battle
		. new(
			battle_cfg,
			[
				BattleSetup.make_pet_input(battle_cfg, 1011, 40, 950, 2),
				BattleSetup.make_pet_input(battle_cfg, 1002, 40, 950, 2),
			],
			[BattleSetup.make_pet_input(battle_cfg, 1003, 40, 950, 2, {"strategy": "focus_weak"})],
			3
		)
	)
	var taunter: Dictionary = battle.units[0]
	var weak_ally: Dictionary = battle.units[1]
	var enemy: Dictionary = battle.units[2]
	taunter.rage = float(battle_cfg.g.RAGE_MAX)
	taunter.stats.spd = 1000
	weak_ally.stats.spd = 1
	weak_ally.hp = 1
	enemy.stats.spd = 500

	var result: Dictionary = battle.run()
	var enemy_hit := _find_attack_result(result.log, String(taunter.name), String(weak_ally.name))
	assert_bool(enemy_hit.contains(String(taunter.name))).is_true()
	assert_int(enemy.tauntTarget).is_equal(int(taunter.uid))
	assert_int(enemy.tauntRemain).is_equal(1)


## 技能习得：仅装配 learnLv 不高于单位等级的技能
func test_skills_are_filtered_by_learn_level() -> void:
	var battle := Battle.new(
		_cfg,
		[BattleSetup.make_pet_input(_cfg, 1001, 1, 900, 0)],
		[BattleSetup.make_pet_input(_cfg, 1003, 1, 900, 0)],
		1
	)
	var skill_ids: Array[int] = []
	for skill in battle.units[0].skills:
		skill_ids.append(int(skill.skillId))
	assert_array(skill_ids).is_equal([1, 2])
	assert_int(battle.units[0].cds.size()).is_equal(2)


func _find_log(lines: Array, needle: String) -> int:
	for index in range(lines.size()):
		if String(lines[index]).contains(needle):
			return index
	return -1


func _find_attack_result(lines: Array, first_name: String, second_name: String) -> String:
	for line in lines:
		var text := String(line)
		if (
			(text.contains(first_name) or text.contains(second_name))
			and (text.contains("受到") or text.contains("护盾吸收"))
		):
			return text
	return ""


## 冒烟 V-501：表引用完整性（关卡波次/掉落引用、技能池、首发灵宠数）
func test_smoke_v501_table_refs() -> void:
	var stage: Array = _tables["StageConfig"]
	var groups: Array = _tables["EnemyGroup"]
	var drops: Array = _tables["DropRule"]
	var gids := {}
	for x in groups:
		gids[int(x.groupId)] = true
	var dids := {}
	for x in drops:
		dids[int(x.dropId)] = true
	assert_int(stage.size()).is_greater_equal(6)
	for s in stage:
		for w in s.waves:
			assert_bool(gids.has(int(w))).is_true()
		assert_bool(dids.has(int(s.dropId))).is_true()
	var pet_count := 0
	for pet_id in _cfg.skillPool:
		var skills: Array = _cfg.skillPool[pet_id]
		var present := 0
		for entry in skills:
			if not entry.is_empty() and int(entry.skillId) > 0 and int(entry.learnLv) > 0:
				present += 1
		assert_int(present).is_equal(4)
		pet_count += 1
	assert_int(pet_count).is_equal(12)
	assert_int(_cfg.pets.size()).is_equal(12)
