## doc: 01 §144（修为驱动）/ 02 §3.3（突破门槛）/ 04 §2-§4
## 灵宠成长测试——与 tests/petGrowth.test.ts 同口径
extends GdUnitTestSuite

const G := {
	"BRK_LV2": 15,
	"BRK_LV3": 40,
	"BRK_LV4": 80,
	"BRK_LV5": 120,
	"PET_FEED_XIU_BASE": 50,
	"PET_FEED_XIU_STEP": 10,
}


func test_feed_cost() -> void:
	assert_int(PetGrowth.feed_cost(1, G)).is_equal(50)
	assert_int(PetGrowth.feed_cost(15, G)).is_equal(190)


func test_level_cap() -> void:
	assert_int(PetGrowth.level_cap(0, G)).is_equal(15)
	assert_int(PetGrowth.level_cap(1, G)).is_equal(40)
	assert_int(PetGrowth.level_cap(2, G)).is_equal(80)
	assert_int(PetGrowth.level_cap(4, G)).is_equal(120)
	assert_int(PetGrowth.level_cap(9, G)).is_equal(120)  # 钳制


func test_feed() -> void:
	# 正常：1 级喂养消耗 50
	var r: Dictionary = PetGrowth.feed({"level": 1, "realmBreaks": 0}, 100, G)
	assert_bool(bool(r.ok)).is_true()
	assert_int(int(r.cost)).is_equal(50)
	assert_int(int(r.level)).is_equal(2)
	# 修为不足
	var r2: Dictionary = PetGrowth.feed({"level": 3, "realmBreaks": 0}, 10, G)
	assert_bool(bool(r2.ok)).is_false()
	assert_str(String(r2.reason)).contains("修为不足")
	# 等级帽：0 突破最高 15
	var r3: Dictionary = PetGrowth.feed({"level": 15, "realmBreaks": 0}, 99999, G)
	assert_bool(bool(r3.ok)).is_false()
	assert_str(String(r3.reason)).contains("突破")


func test_breakthrough() -> void:
	var pet_row := {"breaks": "幼兽;成兽;开灵;完全体;太古体", "aptitudes": [], "natures": ""}
	# 等级不足（需 15）
	var r: Dictionary = PetGrowth.breakthrough({"level": 10, "realmBreaks": 0}, pet_row, 99999, G)
	assert_bool(bool(r.ok)).is_false()
	assert_str(String(r.reason)).contains("等级不足")
	# 达标：消耗 500×1.6^0 = 500
	var r2: Dictionary = PetGrowth.breakthrough({"level": 15, "realmBreaks": 0}, pet_row, 600, G)
	assert_bool(bool(r2.ok)).is_true()
	assert_int(int(r2.cost)).is_equal(500)
	assert_int(int(r2.realmBreaks)).is_equal(1)
	# 修为不足
	var r3: Dictionary = PetGrowth.breakthrough({"level": 15, "realmBreaks": 0}, pet_row, 400, G)
	assert_bool(bool(r3.ok)).is_false()
	# 4 突破封顶
	var r4: Dictionary = PetGrowth.breakthrough({"level": 120, "realmBreaks": 4}, pet_row, 99999, G)
	assert_bool(bool(r4.ok)).is_false()
