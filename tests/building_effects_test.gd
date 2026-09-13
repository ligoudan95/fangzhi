## doc: 05 §2（建筑效果）/ 26 §4.1
## 建筑效果测试——与 tests/buildingEffects.test.ts 同口径
extends GdUnitTestSuite

## 与 Building.csv 同字面量（数值权威走表）
const ROWS := [
	{"buildingId": 1, "maxLevel": 10, "effectKind": 1, "effectBase": 0, "effectStep": 1},
	{"buildingId": 4, "maxLevel": 6, "effectKind": 1, "effectBase": 3, "effectStep": 1},
	{"buildingId": 5, "maxLevel": 6, "effectKind": 1, "effectBase": 1, "effectStep": 1},
	{"buildingId": 7, "maxLevel": 5, "effectKind": 3, "effectBase": 1, "effectStep": 0.5},
	{"buildingId": 8, "maxLevel": 5, "effectKind": 3, "effectBase": 1, "effectStep": 0.5},
	{"buildingId": 9, "maxLevel": 6, "effectKind": 2, "effectBase": 1, "effectStep": 0.5},
	{"buildingId": 12, "maxLevel": 5, "effectKind": 1, "effectBase": 12, "effectStep": 12},
]
const G := {"OFFLINE_CAP_BASE_SEC": 43200, "OFFLINE_CAP_TOTEM_SEC": 86400}


func test_effect_value() -> void:
	assert_float(BuildingEffects.effect_value([], BuildingEffects.FARM, ROWS)).is_equal(3.0)
	(
		assert_float(
			BuildingEffects.effect_value(
				[{"buildingId": 4, "level": 2}], BuildingEffects.FARM, ROWS
			)
		)
		. is_equal(5.0)
	)
	(
		assert_float(
			BuildingEffects.effect_value(
				[{"buildingId": 9, "level": 2}], BuildingEffects.WAREHOUSE, ROWS
			)
		)
		. is_equal(2.0)
	)


func test_slots_queue_mult() -> void:
	var b: Array = [
		{"buildingId": 4, "level": 1}, {"buildingId": 5, "level": 2}, {"buildingId": 7, "level": 3}
	]
	assert_int(BuildingEffects.field_slots(b, ROWS)).is_equal(4)
	assert_int(BuildingEffects.mine_slots(b, ROWS)).is_equal(3)
	assert_int(BuildingEffects.queue_cap(b, BuildingEffects.FORGE, ROWS)).is_equal(2)
	assert_int(BuildingEffects.queue_cap([], BuildingEffects.ALCHEMY, ROWS)).is_equal(1)
	assert_float(BuildingEffects.storage_cap_mult([{"buildingId": 9, "level": 2}], ROWS)).is_equal(
		2.0
	)
	assert_float(BuildingEffects.storage_cap_mult([], ROWS)).is_equal(1.0)


func test_totem_offline_cap() -> void:
	assert_int(BuildingEffects.offline_cap_sec([], ROWS, G)).is_equal(43200)
	assert_int(BuildingEffects.offline_cap_sec([{"buildingId": 12, "level": 1}], ROWS, G)).is_equal(
		86400
	)
	assert_int(BuildingEffects.offline_cap_sec([{"buildingId": 12, "level": 5}], ROWS, G)).is_equal(
		86400
	)


func test_hall_upgrade_cap() -> void:
	var b: Array = [{"buildingId": 1, "level": 2}]
	assert_int(BuildingEffects.upgrade_cap(b, BuildingEffects.FARM, ROWS)).is_equal(2)
	assert_int(BuildingEffects.upgrade_cap(b, BuildingEffects.HALL, ROWS)).is_equal(10)
	assert_int(BuildingEffects.upgrade_cap([], BuildingEffects.FARM, ROWS)).is_equal(0)
