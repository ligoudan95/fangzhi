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
		for id in skills:
			if int(id) != 0:
				present += 1
		assert_int(present).is_equal(4)
		pet_count += 1
	assert_int(pet_count).is_equal(12)
	assert_int(_cfg.pets.size()).is_equal(12)
