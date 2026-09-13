## doc: 08 §7（套装特殊机制）—引擎钩子行为测试（对拍场景10验证 GD/TS 镜像一致性）
## 直接驱动 Battle 内部：手动构造状态调用 _deal_damage/_apply_effect，断言各键数值生效。
extends GdUnitTestSuite

var _tables: Dictionary = {}
var _cfg: Dictionary = {}
var _g: Dictionary = {}


func before_test() -> void:
	_tables = BattleSetup.load_tables("res://resources/config/")
	_cfg = BattleSetup.build_cfg(_tables)
	_g = _cfg.g


func _make_battle(set_bonuses: Dictionary, pet_id: int = 1001) -> Battle:
	var input := BattleSetup.make_pet_input(_cfg, pet_id, 12, 900, 1)
	input["setBonuses"] = set_bonuses
	return Battle.new(_cfg, [input], BattleSetup.group_inputs(_tables, _cfg, 1), 42)


func _units(b: Battle) -> Array:
	return b.units


func test_dmg_first_only_when_faster() -> void:
	var b := _make_battle({"dmg_first": 0.4})
	var u: Dictionary = _units(b)[0]
	var t: Dictionary = _units(b)[1]
	var faster: bool = b.eff(u).spd > b.eff(t).spd
	t.hp = 100000
	b._deal_damage(u, t, 100, 1)
	var loss := 100000 - int(t.hp)
	assert_int(loss).is_equal(roundi(100.0 * 1.4) if faster else 100)


func test_dmg_fire_on_fire_element_attacker() -> void:
	var b := _make_battle({"dmg_fire": 0.15}, 1006)  # 1006 岩浆兽=火元素
	var u: Dictionary = _units(b)[0]
	assert_int(int(u.element)).is_equal(4)
	var t: Dictionary = _units(b)[1]
	t.hp = 100000
	b._deal_damage(u, t, 100, 1)
	assert_int(100000 - int(t.hp)).is_equal(115)


func test_dmg_frozen_vs_frozen_target() -> void:
	var b := _make_battle({"dmg_frozen": 0.5})
	var u: Dictionary = _units(b)[0]
	var t: Dictionary = _units(b)[1]
	t.hp = 100000
	b._deal_damage(u, t, 100, 1)
	var base_loss := 100000 - int(t.hp)
	# 目标挂冰冻（control=1）→ ×1.5
	t.buffs.append({"def": {"control": 1, "kind": 2, "ctrlRes": 0.0}, "stacks": 1, "remain": 2})
	t.hp = 100000
	b._deal_damage(u, t, 100, 1)
	assert_int(100000 - int(t.hp)).is_equal(roundi(float(base_loss) * 1.5))


func test_rage_double_on_hit() -> void:
	var b := _make_battle({})
	var u: Dictionary = _units(b)[0]
	var t: Dictionary = _units(b)[1]
	t.setBonuses = {"rage_double": 2}
	t.rage = 0.0
	t.hp = 100000
	b._deal_damage(u, t, 10, 1)
	assert_float(float(t.rage)).is_equal_approx(float(_g.RAGE_HIT) * 2.0, 0.001)


func test_heal_and_shield_heal() -> void:
	var b := _make_battle({"heal": 0.2, "shield_heal": 0.15}, 1002)  # 桃夭狐（治疗系）
	var u: Dictionary = _units(b)[0]
	var t: Dictionary = u
	t.hp = 0
	t.shield = 0
	var heal_effect := {"type": "Heal", "power": 0.5, "onSelf": false, "chance": 1.0}
	var skill := {"element": 1}
	b._apply_effect(u, skill, heal_effect, [t])
	var healed := int(t.hp)
	# 引擎口径：先 round(mag×power) 再乘治疗加成后 round（双重舍入与 engine 一致）
	assert_int(healed).is_equal(roundi(roundi(b.eff(u).mag * 0.5) * 1.2))
	assert_int(int(t.shield)).is_equal(roundi(float(healed) * 0.15))


func test_cd_reduce_ticks_faster() -> void:
	var b := _make_battle({"cd_reduce": 1})
	var u: Dictionary = _units(b)[0]
	u.cds = [2, 3]
	b._round_end()
	assert_int(int(u.cds[0])).is_equal(0)  # 2 - (1+1) = 0
	assert_int(int(u.cds[1])).is_equal(1)  # 3 - 2 = 1
