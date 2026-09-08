## doc: 13 §5 / 07 §3
## ConfigService 验收——加载 resources/config/*.json（npm run sync:godot 产物）、
## 行表/字典表接口、GlobalConst 取值与缺键兜底。
extends GdUnitTestSuite

const ConfigServiceScript := preload("res://scripts/config/config_service.gd")


func _make_service() -> Node:
	var cs := ConfigServiceScript.new()
	cs.load_all()
	return cs


func test_load_all_tables() -> void:
	var cs := _make_service()
	assert_bool(cs.is_loaded()).is_true()
	# 11 张表全部就位（导表产物清单）
	for table_name in [
		"GlobalConst",
		"PetBase",
		"SkillConfig",
		"BuffConfig",
		"PetSkillPool",
		"EnemyGroup",
		"StageConfig",
		"DropRule",
		"Crop",
		"MainQuest",
		"Enums",
	]:
		assert_bool(cs.get_table(table_name).size() > 0).is_true()
	cs.free()


func test_row_tables_are_arrays() -> void:
	var cs := _make_service()
	assert_int(cs.get_rows("PetBase").size()).is_greater(0)
	assert_bool(cs.get_rows("GlobalConst").is_empty()).is_true()  # 字典表不可作行表
	cs.free()


func test_global_const_getters() -> void:
	var cs := _make_service()
	assert_float(cs.get_g("BRK_M2")).is_equal_approx(1.15, 0.0001)
	assert_float(cs.get_g("MIT_CAP")).is_equal_approx(0.7, 0.0001)
	assert_float(cs.get_g("__MISSING__")).is_equal(0.0)  # 缺键报错并兜底 0
	cs.free()


func test_load_all_is_idempotent() -> void:
	var cs := _make_service()
	cs.load_all()  # 二次加载不得重复入表或报错
	assert_int(cs.get_rows("StageConfig").size()).is_greater(0)
	cs.free()
