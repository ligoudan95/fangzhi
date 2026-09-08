## doc: 02 §3.3 / §8.2（V-401）
## 战力锚点验收——TS 基准 tests/statsAnchors.test.ts 的逐项平移；
## 黄金值取自 TS 实算（src/battle/stats.ts，2026-09-08），双侧任何公式
## 改动导致漂移时：先修 bug，再同步更新两侧黄金值。
extends GdUnitTestSuite

var _g: Dictionary = {}


func before_test() -> void:
	if not _g.is_empty():
		return
	var text := FileAccess.get_file_as_string("res://resources/config/GlobalConst.json")
	assert_that(text).is_not_empty()
	_g = JSON.parse_string(text)


## 突破倍率分段正确（02 §3.3）
func test_break_mult_segments() -> void:
	assert_float(BattleStats.break_mult(1, _g)).is_equal_approx(1.0, 0.000001)
	assert_float(BattleStats.break_mult(15, _g)).is_equal_approx(_g["BRK_M2"], 0.000001)
	assert_float(BattleStats.break_mult(40, _g)).is_equal_approx(_g["BRK_M3"], 0.000001)
	assert_float(BattleStats.break_mult(80, _g)).is_equal_approx(_g["BRK_M4"], 0.000001)
	assert_float(BattleStats.break_mult(120, _g)).is_equal_approx(_g["BRK_M5"], 0.000001)


## 等级-战力锚点 ±15%（V-401）：物理模板 资质1000 无偏移 无装备
func test_power_anchors_v401() -> void:
	var apt := {"atk": 1000, "def": 1000, "hp": 1000, "spd": 1000, "mag": 1000}
	var off := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "mag": 0.0, "res": 0.0}
	var anchors := [
		[15, 1, "ANCHOR_POW_15"],
		[40, 2, "ANCHOR_POW_40"],
		[80, 4, "ANCHOR_POW_80"],
		[120, 8, "ANCHOR_POW_120"],
	]
	for a in anchors:
		var p := BattleStats.power_of(BattleStats.compute_stats(1, off, a[0], apt, a[1], _g), _g)
		var anchor: float = _g[a[2]]
		var dev := absf(p - anchor) / anchor
		assert_float(dev).is_less_equal(float(_g["ANCHOR_TOL"]))


## 跨引擎黄金值：与 TS 实算逐项全等（六维 + 战力）——D3 对拍基准
func test_stats_match_ts_golden() -> void:
	var apt := {"atk": 1000, "def": 1000, "hp": 1000, "spd": 1000, "mag": 1000}
	var off := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "mag": 0.0, "res": 0.0}
	var golden := [
		[15, 1, 1613, 176, 105, 112, 62, 62, 1253],
		[40, 2, 4321, 470, 280, 286, 164, 164, 3308],
		[80, 4, 12145, 1318, 786, 784, 459, 459, 9233],
		[120, 8, 36384, 3946, 2354, 2325, 1372, 1372, 27583],
	]
	for a in golden:
		var s := BattleStats.compute_stats(1, off, a[0], apt, a[1], _g)
		assert_int(s["hp"]).is_equal(a[2])
		assert_int(s["atk"]).is_equal(a[3])
		assert_int(s["def"]).is_equal(a[4])
		assert_int(s["spd"]).is_equal(a[5])
		assert_int(s["mag"]).is_equal(a[6])
		assert_int(s["res"]).is_equal(a[7])
		assert_int(BattleStats.power_of(s, _g)).is_equal(a[8])


## 抗性成长随灵力资质（v0 简化）：资质 500 时 res 成长减半的口径与 TS 一致
func test_res_uses_mag_aptitude() -> void:
	var off := {"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "mag": 0.0, "res": 0.0}
	var s := BattleStats.compute_stats(
		1, off, 10, {"atk": 1000, "def": 1000, "hp": 1000, "spd": 1000, "mag": 500}, 0, _g
	)
	# 模板1：res = 20 + 10×1.8×0.5 = 29（若误用整除或错引 res 资质则不等）
	assert_int(s["res"]).is_equal(29)
