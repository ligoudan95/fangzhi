## doc: 08 §4/§5/§7（穿戴管线）
## 装备属性修正测试——与 tests/equipStats.test.ts 同口径
extends GdUnitTestSuite

var _ec: Dictionary = {}
var _sets: Array = []
var _g: Dictionary = {}


func before_test() -> void:
	var tables := BattleSetup.load_tables("res://resources/config/")
	_ec = BattleSetup.build_equip_config(tables)
	_sets = tables.get("EquipSet", [])
	_g = tables.get("GlobalConst", {})


func _item(equip_id: int, instance: String) -> Dictionary:
	# 白品 0 级：无词条，主属性 = baseValue，数值可手算
	return {
		"instanceId": instance,
		"equipId": equip_id,
		"quality": 0,
		"level": 0,
		"rollSeed": 12345,
		"identified": true,
		"enhanceLevel": 0,
	}


func test_main_stat_flat() -> void:
	# 武器 101 主 atk 基准 32（0 级白品无词条）
	var pet := {"equips": {1: "a"}}
	var mods: Dictionary = EquipStats.equipped_mods(pet, [_item(101, "a")], _ec, _sets, _g)
	assert_int(int(mods.flat.get("atk", 0))).is_equal(32)
	assert_float(float(mods.ratio.get("atk", 0.0))).is_equal(0.0)


func test_enhance_multiplier_applies() -> void:
	# 强化 +3：×1.15 → 32×1.15 = 36.8 → 37
	var item := _item(101, "a")
	item.enhanceLevel = 3
	var mods: Dictionary = EquipStats.equipped_mods(
		[{"equips": {1: "a"}}][0], [item], _ec, _sets, _g
	)
	assert_int(int(mods.flat.get("atk", 0))).is_equal(37)


func test_unidentified_and_missing_skip() -> void:
	var unidentified := _item(101, "a")
	unidentified.identified = false
	var mods: Dictionary = EquipStats.equipped_mods(
		{"equips": {1: "a", 2: "ghost"}}, [unidentified], _ec, _sets, _g
	)
	assert_int(mods.flat.size()).is_equal(0)


func test_set_two_piece_ratio_and_three_piece_special() -> void:
	# 狼魂（setId 1）：101 武器 + 301 饰品 → 2 件 spd +12% 进 ratio
	var items: Array = [_item(101, "w"), _item(301, "t"), _item(201, "a")]
	var two: Dictionary = EquipStats.equipped_mods(
		{"equips": {1: "w", 3: "t"}}, items, _ec, _sets, _g
	)
	assert_float(float(two.ratio.get("spd", 0.0))).is_equal(0.12)
	assert_int(two.activeSets.size()).is_equal(1)
	# 3 件：bonus3 = 先手伤害+40%（dmg_first 非六维 → special 登记）
	var three: Dictionary = EquipStats.equipped_mods(
		{"equips": {1: "w", 2: "a", 3: "t"}}, items, _ec, _sets, _g
	)
	assert_int(three.activeSets[0].tier).is_equal(3)
	assert_int(three.special.size()).is_equal(1)
	assert_str(String(three.special[0])).contains("狼魂")
	# spd 2 件修正仍在
	assert_float(float(three.ratio.get("spd", 0.0))).is_equal(0.12)
