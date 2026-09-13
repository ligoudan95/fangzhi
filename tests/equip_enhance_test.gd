## doc: 08 §7——与 TS 基准 tests/equipEnhance.test.ts 同口径
extends GdUnitTestSuite


func test_enhance_cost_escalates() -> void:
	var c0: Dictionary = EquipEnhance.enhance_cost(0)
	var c5: Dictionary = EquipEnhance.enhance_cost(5)
	assert_int(int(c0.metalIngot)).is_equal(1)
	assert_int(int(c5.metalIngot)).is_equal(6)
	assert_int(int(c5.spiritCrystal)).is_greater(int(c0.spiritCrystal))


func test_success_rate_decreases() -> void:
	assert_float(EquipEnhance.enhance_success_rate(0)).is_equal(1.0)
	assert_float(EquipEnhance.enhance_success_rate(3)).is_less(1.0)
	assert_float(EquipEnhance.enhance_success_rate(10)).is_less(
		EquipEnhance.enhance_success_rate(7)
	)


func test_max_level_capped() -> void:
	assert_int(EquipEnhance.max_enhance_level(1)).is_equal(3)
	assert_int(EquipEnhance.max_enhance_level(10)).is_equal(15)


func test_set_bonus_tiers() -> void:
	var active: Dictionary = EquipEnhance.active_set_bonus([1, 1, 1, 2, 2, 3])
	assert_int(int(active[1].tier)).is_equal(3)
	assert_int(int(active[2].tier)).is_equal(2)
	assert_bool(active.has(3)).is_false()


func test_enhance_multiplier() -> void:
	assert_float(EquipEnhance.enhance_multiplier(0)).is_equal(1.0)
	assert_float(EquipEnhance.enhance_multiplier(5)).is_equal(1.25)
	assert_float(EquipEnhance.enhance_multiplier(15)).is_equal(1.75)
