## doc: 08 M3 Phase 0 契约 / 14 R-P1-02
## TS 基准 tests/equipment_drop.test.ts 的断言口径平移；黄金值与 TS 同字面量。
extends GdUnitTestSuite

var _ec: Dictionary = {}
var _g: Dictionary = {}


func before_test() -> void:
	if _ec.is_empty():
		var tables := BattleSetup.load_tables("res://resources/config/")
		_ec = BattleSetup.build_equip_config(tables)
		_g = tables.get("GlobalConst", {})


func _req(over: Dictionary = {}) -> Dictionary:
	var request := {
		"rootSeed": 424242,
		"settlementSeq": 1,
		"dropId": 2,
		"dropCount": 2,
		"monsterLevel": 20,
		"luckValue": 0.0,
		"pityState": EquipDropResolver.empty_pity_state(),
	}
	for k in over:
		request[k] = over[k]
	return request


## RNG 派生黄金值：与 TS 基准逐位一致（锁死双端 u32 语义）
func test_rng_derivation_golden() -> void:
	var settle := EquipDropRng.derive_settlement_seed(123, 456, 7)
	assert_int(settle).is_equal(532854096)
	assert_int(EquipDropRng.derive_item_seed(settle, 0)).is_equal(3555727561)
	assert_int(EquipDropRng.derive_item_seed(settle, 2)).is_equal(3082722033)
	(
		assert_int(
			EquipDropRng.derive_stream_seed(
				EquipDropRng.derive_item_seed(settle, 0), EquipDropRng.TAG_QUALITY
			)
		)
		. is_equal(3532353615)
	)
	assert_int(EquipDropRng.derive_stream_seed(settle, EquipDropRng.TAG_PITY_INDEX)).is_equal(
		1999517938
	)


## 确定性：同请求两次结算逐字段一致（含 canonicalLog）
func test_settlement_determinism() -> void:
	var a: Dictionary = EquipDropResolver.resolve_settlement(_req(), _ec, _g)
	var b: Dictionary = EquipDropResolver.resolve_settlement(_req(), _ec, _g)
	assert_str(String(a.error)).is_equal(String(b.error))
	assert_array(a.canonicalLog).is_equal(b.canonicalLog)
	assert_int(a.items.size()).is_equal(b.items.size())
	for i in range(a.items.size()):
		assert_str(String(a.items[i].instanceId)).is_equal(String(b.items[i].instanceId))
		assert_int(int(a.items[i].rollSeed)).is_equal(int(b.items[i].rollSeed))


## 幸运值：仅稀有档权重放大，luck=0 等于原表
func test_apply_luck_only_rare_rows() -> void:
	var rule: Dictionary = _ec.rules[2]
	var base: Array = EquipDropResolver.apply_luck(rule, _ec.qualities, 0.0)
	assert_array(base).is_equal(rule.weights)
	var lucky: Array = EquipDropResolver.apply_luck(rule, _ec.qualities, 1000.0)
	assert_float(float(lucky[3])).is_equal_approx(float(rule.weights[3]) * 2.0, 0.0001)
	assert_float(float(lucky[0])).is_equal(float(rule.weights[0]))


## 保底：注入 before=14 后首个未自然命中的结算触发，强制紫+并清零
func test_pity_forces_quality_at_threshold() -> void:
	var rule: Dictionary = _ec.rules[2]
	var state := {"schemaVersion": 1, "counters": {"2": 14}}
	var triggered: Dictionary = {}
	for seq in range(100, 160):
		var s: Dictionary = EquipDropResolver.resolve_settlement(
			_req({"settlementSeq": seq, "pityState": state, "dropCount": 1}), _ec, _g
		)
		if bool(s.pityTriggered):
			triggered = s
			break
		state.counters["2"] = int(s.pityAfter.counters["2"])
	assert_bool(triggered.is_empty()).is_false()
	var hit := false
	for item in triggered.items:
		if int(item.quality) >= int(rule.pityQuality):
			hit = true
	assert_bool(hit).is_true()
	assert_int(int(triggered.pityAfter.counters["2"])).is_equal(0)


## 词条：数量在品质区间内、stat 不重复、数值在缩放区间内
func test_affixes_in_bounds_and_unique() -> void:
	for seq in range(1, 201):
		var s: Dictionary = EquipDropResolver.resolve_settlement(
			_req({"settlementSeq": seq, "dropCount": 2, "dropId": 3, "monsterLevel": 30}), _ec, _g
		)
		assert_str(String(s.error)).is_empty()
		for item in s.items:
			var q: Dictionary = _ec.qualities[int(item.quality)]
			assert_int(item.affixes.size()).is_between(int(q.affixMin), int(q.affixMax))
			var stats := {}
			for a in item.affixes:
				assert_bool(stats.has(String(a.stat))).is_false()
				stats[String(a.stat)] = true
				var row: Dictionary = {}
				for r in _ec.affixes:
					if int(r.affixId) == int(a.affixId):
						row = r
						break
				var lo := (
					float(row.min) * (1.0 + float(item.level) * float(_g.EQUIP_AFFIX_LV_SCALE))
				)
				var hi := (
					float(row.max) * (1.0 + float(item.level) * float(_g.EQUIP_AFFIX_LV_SCALE))
				)
				assert_int(int(a.valueMicro)).is_between(
					floori(lo * 1000000.0) - 1, ceili(hi * 1000000.0) + 1
				)


## 未鉴定封装：蓝及以上 identified=false，白绿直接鉴定
func test_unidentified_by_quality() -> void:
	var samples := {}
	var seq := 1000
	while seq < 4000 and samples.keys().size() < 6:
		var s: Dictionary = EquipDropResolver.resolve_settlement(
			_req({"settlementSeq": seq, "dropCount": 2, "dropId": 1}), _ec, _g
		)
		for item in s.items:
			samples[int(item.quality)] = bool(item.identified)
		seq += 1
	assert_bool(samples.get(0, true)).is_true()
	if samples.has(2):
		assert_bool(samples[2]).is_false()


## 鉴定幂等：重复鉴定一致，且与掉落时展开一致
func test_identification_idempotent_matches_drop() -> void:
	var s: Dictionary = EquipDropResolver.resolve_settlement(
		_req({"settlementSeq": 42, "dropCount": 3, "dropId": 3, "monsterLevel": 25}), _ec, _g
	)
	for item in s.items:
		var a: Dictionary = EquipDropResolver.resolve_identification(item, _ec, _g)
		var b: Dictionary = EquipDropResolver.resolve_identification(item, _ec, _g)
		assert_str(String(a.error)).is_empty()
		assert_int(int(a.mainValueMicro)).is_equal(int(b.mainValueMicro))
		assert_int(a.affixes.size()).is_equal(item.affixes.size())
		for i in range(a.affixes.size()):
			assert_int(int(a.affixes[i].affixId)).is_equal(int(item.affixes[i].affixId))
			assert_int(int(a.affixes[i].valueMicro)).is_equal(int(item.affixes[i].valueMicro))
		assert_int(int(a.mainValueMicro)).is_greater(0)


## 装备等级：monster_level 基准 ± 偏移，最低受 EQUIP_LEVEL_MIN 钳制
func test_equip_level_clamped() -> void:
	var s: Dictionary = EquipDropResolver.resolve_settlement(
		_req({"settlementSeq": 7, "dropCount": 4, "dropId": 1, "monsterLevel": 1}), _ec, _g
	)
	for item in s.items:
		assert_int(int(item.level)).is_greater_equal(int(_g.EQUIP_LEVEL_MIN))
		assert_int(int(item.level)).is_less_equal(3)


## 非法输入：未知 dropId / 越界 dropCount 返回 error 且不改 pity
func test_invalid_requests_fail_cleanly() -> void:
	var bad1: Dictionary = EquipDropResolver.resolve_settlement(_req({"dropId": 999}), _ec, _g)
	assert_str(String(bad1.error)).is_not_empty()
	var bad2: Dictionary = EquipDropResolver.resolve_settlement(_req({"dropCount": 0}), _ec, _g)
	assert_str(String(bad2.error)).is_not_empty()
	assert_int(int(bad2.pityAfter.counters.size())).is_equal(0)
