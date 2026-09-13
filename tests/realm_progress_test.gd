## doc: 02 §2.2（境界修为曲线）/ 01 §144
## 玩家境界测试——与 tests/realmProgress.test.ts 同口径
extends GdUnitTestSuite

const G := {
	"REALM_BASE_XIU": 500.0, "REALM_BASE_GROWTH": 2.6, "REALM_LAYER_GROWTH": 1.35, "REALM_LAYERS": 9
}


func test_layer_cost() -> void:
	# 淬体一重 = 500；淬体二重 = 500×1.35 = 675
	assert_int(RealmProgress.layer_cost(1, 1, G)).is_equal(500)
	assert_int(RealmProgress.layer_cost(1, 2, G)).is_equal(675)
	# 凝血一重 = 500×2.6 = 1300
	assert_int(RealmProgress.layer_cost(2, 1, G)).is_equal(1300)


func test_try_advance() -> void:
	# 修为不足
	var r: Dictionary = RealmProgress.try_advance(499, 1, 1, G)
	assert_bool(bool(r.ok)).is_false()
	assert_int(int(r.cost)).is_equal(500)
	# 足够 → 二重
	var r2: Dictionary = RealmProgress.try_advance(600, 1, 1, G)
	assert_bool(bool(r2.ok)).is_true()
	assert_int(int(r2.cost)).is_equal(500)
	assert_int(int(r2.realmLayer)).is_equal(2)
	# 九重满 → 进境归一
	var r3: Dictionary = RealmProgress.try_advance(999999, 1, 9, G)
	assert_int(int(r3.realmId)).is_equal(2)
	assert_int(int(r3.realmLayer)).is_equal(1)
	# 荒神九重封顶
	var r4: Dictionary = RealmProgress.try_advance(999999999, 10, 9, G)
	assert_bool(bool(r4.ok)).is_false()
	assert_str(String(r4.reason)).is_equal("已达十境之巅")


func test_unlock_gate() -> void:
	assert_int(RealmProgress.realm_of_name("淬体")).is_equal(1)
	assert_int(RealmProgress.realm_of_name("凝血")).is_equal(2)
	assert_int(RealmProgress.realm_of_name("通脉")).is_equal(3)
	assert_bool(RealmProgress.can_unlock("淬体", 1)).is_true()
	assert_bool(RealmProgress.can_unlock("凝血", 1)).is_false()
	assert_bool(RealmProgress.can_unlock("凝血", 2)).is_true()
	# 未知名 → 视为无门槛（1）
	assert_bool(RealmProgress.can_unlock("不存在的境", 1)).is_true()


func test_display() -> void:
	assert_str(RealmProgress.realm_display(1, 1, G)).is_equal("淬体一重")
	assert_str(RealmProgress.realm_display(1, 3, G)).is_equal("淬体三重")
	assert_str(RealmProgress.realm_display(1, 9, G)).is_equal("淬体九重")
	assert_str(RealmProgress.realm_display(2, 1, G)).is_equal("凝血一重")
