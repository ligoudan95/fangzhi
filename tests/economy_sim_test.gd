## doc: 18 §3 / 04 §1——与 TS 基准 tests/economySim.test.ts 同口径
extends GdUnitTestSuite

const SEASONS := {
	0: {"farmMult": 1.2, "mineMult": 1.0},
	1: {"farmMult": 1.0, "mineMult": 1.0},
	2: {"farmMult": 1.3, "mineMult": 1.0},
	3: {"farmMult": 0.5, "mineMult": 0.7},
}
const ALL_IDS: Array = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012]


func test_normal_30d_positive_balance() -> void:
	var r: Dictionary = EconomySim.simulate(EconomySim.Profile.NORMAL, 30, 5, {"seasons": SEASONS})
	assert_int(r.dailyLog.size()).is_equal(30)
	assert_int(int(r.inventory["兽贝"])).is_greater(0)


func test_idle_less_than_active() -> void:
	var idle: Dictionary = EconomySim.simulate(EconomySim.Profile.IDLE, 30, 5, {"seasons": SEASONS})
	var active: Dictionary = EconomySim.simulate(
		EconomySim.Profile.ACTIVE, 30, 5, {"seasons": SEASONS}
	)
	assert_int(int(active.inventory["兽贝"])).is_greater(int(idle.inventory["兽贝"]))


func test_winter_lowest_harvest() -> void:
	var r: Dictionary = EconomySim.simulate(EconomySim.Profile.NORMAL, 20, 5, {"seasons": SEASONS})
	var spring_total := 0
	var winter_total := 0
	for d in r.dailyLog:
		if int(d.season) == 0:
			spring_total += int(d.harvest)
		elif int(d.season) == 3:
			winter_total += int(d.harvest)
	assert_int(winter_total).is_less(spring_total)


func test_codex_luck() -> void:
	var pets: Array = [{"petId": 1001}, {"petId": 1002}, {"petId": 1003}]
	assert_float(CodexSystem.completion_ratio(pets, ALL_IDS)).is_equal(0.25)
	assert_int(CodexSystem.luck_bonus(pets, ALL_IDS)).is_equal(50)
