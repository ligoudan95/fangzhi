## doc: 15 §2 / 26 §3
## 村落生产结算测试——与 TS 基准 tests/villageProduction.test.ts 同口径同字面量。
extends GdUnitTestSuite

var _config: Dictionary = {}


func before_test() -> void:
	if _config.is_empty():
		var crops := {}
		crops[1] = {"cropId": 1, "growMin": 30, "yieldN": 6, "outputItemId": 101, "outputCount": 6}
		crops[5] = {"cropId": 5, "growMin": 240, "yieldN": 3, "outputItemId": 105, "outputCount": 3}
		var seasons := {}
		seasons[0] = {"farmMult": 1.2}
		seasons[1] = {"farmMult": 1.0}
		seasons[2] = {"farmMult": 1.3}
		seasons[3] = {"farmMult": 0.5}
		var category_of := {101: 3, 105: 2}
		var rules := {2: 150, 3: 100}
		_config = {
			"crops": crops,
			"seasons": seasons,
			"categoryOf": category_of,
			"storageRules": rules,
			"g":
			{
				"SEASON_EPOCH_UTC_SEC": 0,
				"OFFLINE_CAP_BASE_SEC": 43200,
				"STORAGE_DECAY_PCT": 0.1,
				"STORAGE_DECAY_PERIOD_SEC": 86400,
			},
		}


func _fields() -> Array:
	return [{"slotId": 1, "cropId": 1, "startedAtUtcSec": 0}]


## 软容量入库：可超上限保留并报告超量
func test_add_item_soft_cap() -> void:
	var res: Dictionary = InventoryLedger.add_item(
		[], 101, 120, _config.categoryOf, _config.storageRules
	)
	assert_str(String(res.error)).is_empty()
	assert_int(int(res.stored)).is_equal(120)
	assert_int(int(res.cap)).is_equal(100)
	assert_int(int(res.overflow)).is_equal(20)
	assert_int(res.stacks.size()).is_equal(1)


## 溢出衰减：单周期扣超额 10%（120/100 → 扣 2）
func test_overflow_decay_single_period() -> void:
	var stacks: Array = [{"itemId": 101, "amount": 60}, {"itemId": 107, "amount": 60}]
	var res: Dictionary = InventoryLedger.apply_overflow_decay(stacks, [101, 107], 100, 1, 0.1)
	assert_int(int(res.decayed)).is_equal(2)
	var total := 0
	for s in res.stacks:
		total += int(s.amount)
	assert_int(total).is_equal(118)


## 衰减确定性：同输入两次结果一致
func test_overflow_decay_deterministic() -> void:
	var stacks: Array = [{"itemId": 105, "amount": 200}]
	var a: Dictionary = InventoryLedger.apply_overflow_decay(stacks, [105], 150, 3, 0.1)
	var b: Dictionary = InventoryLedger.apply_overflow_decay(stacks, [105], 150, 3, 0.1)
	assert_int(a.stacks.size()).is_equal(b.stacks.size())
	assert_int(int(a.decayed)).is_equal(int(b.decayed))
	assert_int(int(a.stacks[0].amount)).is_equal(int(b.stacks[0].amount))


## 作物结算：30 分钟成熟，春 ×1.2 → 7
func test_settle_crops_spring_mult() -> void:
	var r: Dictionary = VillageProduction.settle_crops(_fields(), 0, 1800, [], _config)
	assert_int(r.outputs.size()).is_equal(1)
	assert_int(int(r.outputs[0].itemId)).is_equal(101)
	assert_int(int(r.outputs[0].amount)).is_equal(7)
	assert_int(r.nextFields.size()).is_equal(0)
	assert_int(int(r.inventory[0].amount)).is_equal(7)


## 未到成熟不产出；倒流零结算
func test_settle_crops_immature_and_rollback() -> void:
	var early: Dictionary = VillageProduction.settle_crops(_fields(), 0, 1700, [], _config)
	assert_int(early.outputs.size()).is_equal(0)
	assert_int(early.nextFields.size()).is_equal(1)
	var rollback: Dictionary = VillageProduction.settle_crops(_fields(), 1000, 500, [], _config)
	assert_int(rollback.outputs.size()).is_equal(0)
	assert_int(int(rollback.nextCursor)).is_equal(1000)


## 离线上限：24h 窗口截断到 12h
func test_settle_crops_offline_cap() -> void:
	var r: Dictionary = VillageProduction.settle_crops(_fields(), 0, 86400, [], _config)
	assert_int(int(r.cappedBy)).is_equal(43200)


## 跨季结算：成熟点所在切片决定系数（春 7 / 夏 6）
func test_settle_crops_cross_season() -> void:
	var fields: Array = [
		{"slotId": 1, "cropId": 1, "startedAtUtcSec": 430000},
		{"slotId": 2, "cropId": 1, "startedAtUtcSec": 430300},
	]
	var r: Dictionary = VillageProduction.settle_crops(fields, 430000, 432200, [], _config)
	assert_int(r.outputs.size()).is_equal(2)
	for o in r.outputs:
		if int(o.season) == 0:
			assert_int(int(o.amount)).is_equal(7)
		elif int(o.season) == 1:
			assert_int(int(o.amount)).is_equal(6)


## 幂等：同输入两次结算一致
func test_settle_crops_idempotent() -> void:
	var fields: Array = [{"slotId": 1, "cropId": 5, "startedAtUtcSec": 100}]
	var inv: Array = [{"itemId": 105, "amount": 100}]
	var a: Dictionary = VillageProduction.settle_crops(fields, 0, 90000, inv, _config)
	var b: Dictionary = VillageProduction.settle_crops(fields, 0, 90000, inv, _config)
	assert_int(a.outputs.size()).is_equal(b.outputs.size())
	assert_int(int(a.cappedBy)).is_equal(int(b.cappedBy))
	assert_int(a.inventory.size()).is_equal(b.inventory.size())
	assert_int(int(a.inventory[0].amount)).is_equal(int(b.inventory[0].amount))
