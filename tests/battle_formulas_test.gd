## doc: 02 §4/§5 / 03 §3 / 13 §6
## 伤害管线与捕捉率验收——TS 基准 tests/damage.test.ts + capture.test.ts 断言平移；
## 另含 mulberry32 与 TS makeRng 的黄金值逐位对拍（2026-09-08 实算）。
extends GdUnitTestSuite

var _g: Dictionary = {}


func before_test() -> void:
	if _g.is_empty():
		_g = JSON.parse_string(
			FileAccess.get_file_as_string("res://resources/config/GlobalConst.json")
		)


# ---------- RNG 黄金值（与 TS makeRng 逐位一致） ----------


func test_rng_matches_ts_golden() -> void:
	var golden := {
		42:
		[
			0.6011037519201636,
			0.44829055899754167,
			0.8524657934904099,
			0.6697340414393693,
			0.17481389874592423
		],
		1:
		[
			0.6270739405881613,
			0.002735721180215478,
			0.5274470399599522,
			0.9810509674716741,
			0.9683778982143849
		],
		20260908:
		[
			0.5866398327052593,
			0.7089426536113024,
			0.41529360273852944,
			0.7993595646694303,
			0.8216658711899072
		],
		70000:
		[
			0.42030980670824647,
			0.9392832410521805,
			0.07759617082774639,
			0.7586724886205047,
			0.30367869045585394
		],
	}
	for seed in golden:
		var rng := BattleRng.new(int(seed))
		for expected in golden[seed]:
			assert_float(rng.next()).is_equal_approx(float(expected), 0.000000000000001)


# ---------- 克制与伤害管线（02 §4 / 03 §3） ----------


func _neutral_roll() -> Dictionary:
	return {"hit": true, "crit": false, "float": 1.0}


func test_clash_coefficients() -> void:
	assert_float(Battle.clash(4, 1, _g)).is_equal(1.5)
	assert_float(Battle.clash(1, 2, _g)).is_equal(1.5)
	assert_float(Battle.clash(1, 4, _g)).is_equal(0.75)
	assert_float(Battle.clash(4, 3, _g)).is_equal(0.75)
	assert_float(Battle.clash(1, 3, _g)).is_equal(1.0)


func _base_input() -> Dictionary:
	return {
		"atkStat": 1000,
		"power": 1.5,
		"isPhys": true,
		"attackerElement": 1,
		"defenderElement": 3,
		"skillElement": 0,
		"defStat": 220 * 40,
		"defenderLevel": 40,
		"dmgMod": 1.0,
		"markPct": 0.0,
	}


func test_base_damage_750() -> void:
	var d := Battle.calc_damage(_base_input(), _neutral_roll(), _g)
	assert_int(d).is_equal(750)


func test_clash_and_crit() -> void:
	var inp := _base_input()
	inp["attackerElement"] = 4
	inp["defenderElement"] = 1
	assert_int(Battle.calc_damage(inp, _neutral_roll(), _g)).is_equal(1125)
	var crit := _neutral_roll()
	crit["crit"] = true
	assert_int(Battle.calc_damage(inp, crit, _g)).is_equal(1688)


func test_mark_bonus() -> void:
	var base := _base_input()
	base["attackerElement"] = 4
	base["defenderElement"] = 5
	base["skillElement"] = 4
	base["power"] = 1.0
	base["isPhys"] = false
	var plain := Battle.calc_damage(base, _neutral_roll(), _g)
	base["markPct"] = 0.3
	var marked := Battle.calc_damage(base, _neutral_roll(), _g)
	assert_int(marked).is_equal(roundi(plain * 1.3))


func test_mitigation_cap_70() -> void:
	var inp := _base_input()
	inp["power"] = 1.0
	inp["defStat"] = 5000 * 40
	assert_int(Battle.calc_damage(inp, _neutral_roll(), _g)).is_equal(roundi(1000 * (1.0 - 0.7)))


# ---------- 捕捉率（02 §5） ----------


func test_capture_jade_gourd_beast() -> void:
	var r := (
		Battle
		. compute_capture_rate(
			{
				"gourdBase": _g.CAP_GOURD_JADE,
				"qualityCoef": _g.CAP_Q3,
				"hpPct": 0.15,
				"hasControl": true,
				"hasCaptureDebuff": false,
				"lvlDiff": 0,
				"capBonus": 0.0,
			},
			_g
		)
	)
	assert_float(absf(r - 0.33)).is_less(0.005)


func test_capture_wood_gourd_common() -> void:
	var r := (
		Battle
		. compute_capture_rate(
			{
				"gourdBase": _g.CAP_GOURD_WOOD,
				"qualityCoef": _g.CAP_Q1,
				"hpPct": 0.15,
				"hasControl": false,
				"hasCaptureDebuff": true,
				"lvlDiff": 0,
				"capBonus": 0.0,
			},
			_g
		)
	)
	assert_float(absf(r - 0.42)).is_less(0.005)


func test_capture_montecarlo_1e5() -> void:
	var rate := (
		Battle
		. compute_capture_rate(
			{
				"gourdBase": _g.CAP_GOURD_JADE,
				"qualityCoef": _g.CAP_Q3,
				"hpPct": 0.15,
				"hasControl": true,
				"hasCaptureDebuff": false,
				"lvlDiff": 0,
				"capBonus": 0.0,
			},
			_g
		)
	)
	var rng := BattleRng.new(9527)
	var hits := 0
	for i in range(100000):
		if rng.next() < rate:
			hits += 1
	var sim := float(hits) / 100000.0
	assert_float(absf(sim - rate)).is_less(0.01)


func test_capture_level_penalty_caps() -> void:
	var mk := func(lvl_diff: int) -> float:
		return (
			Battle
			. compute_capture_rate(
				{
					"gourdBase": 0.65,
					"qualityCoef": 1.0,
					"hpPct": 0.1,
					"hasControl": true,
					"hasCaptureDebuff": false,
					"lvlDiff": lvl_diff,
					"capBonus": 0.0,
				},
				_g
			)
		)
	var a: float = mk.call(5)
	var b: float = mk.call(10)
	var c: float = mk.call(99)
	assert_float(a).is_greater(b)
	assert_float(b).is_equal(c)
