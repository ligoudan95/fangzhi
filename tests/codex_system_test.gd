## doc: 04 §1 / 08 §3——与 TS 基准 tests/codexSystem.test.ts 同口径
extends GdUnitTestSuite

const ALL_IDS: Array = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012]


func test_collected_dedup() -> void:
	var pets: Array = [{"petId": 1001}, {"petId": 1001}, {"petId": 1002}]
	assert_int(CodexSystem.collected_ids(pets).size()).is_equal(2)


func test_completion_ratio() -> void:
	var pets: Array = [{"petId": 1001}, {"petId": 1002}, {"petId": 1003}]
	assert_float(CodexSystem.completion_ratio(pets, ALL_IDS)).is_equal(0.25)


func test_luck_bonus() -> void:
	var pets: Array = [{"petId": 1001}, {"petId": 1002}, {"petId": 1003}]
	assert_int(CodexSystem.luck_bonus(pets, ALL_IDS)).is_equal(50)


func test_codex_entries() -> void:
	var rows: Array = []
	for id in ALL_IDS:
		rows.append({"petId": id, "name": "宠%d" % id, "element": 1, "quality": 2})
	var entries: Array = CodexSystem.codex_entries([{"petId": 1001}], rows)
	assert_int(entries.size()).is_equal(12)
	assert_bool(bool(entries[0].captured)).is_true()
	assert_bool(bool(entries[1].captured)).is_false()
