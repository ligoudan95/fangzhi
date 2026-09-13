## doc: 04 §2/§3（资质 roll/性格/突破链）——与 TS 基准 tests/petIndividuality.test.ts 同口径
extends GdUnitTestSuite

var _pets: Array = []
var _g: Dictionary = {}


func before_test() -> void:
	if _pets.is_empty():
		var tables := BattleSetup.load_tables("res://resources/config/")
		_pets = tables.get("PetBase", [])
		_g = tables.get("GlobalConst", {})


func _pet(id: int) -> Dictionary:
	for p in _pets:
		if int(p.petId) == id:
			return p
	return {}


## 资质 roll：同种子确定一致，不同种子有差异，值在范围内
func test_aptitude_roll_deterministic_and_in_range() -> void:
	var pet := _pet(1001)
	var a1: Dictionary = PetIndividuality.roll_aptitudes(pet, 42)
	var a2: Dictionary = PetIndividuality.roll_aptitudes(pet, 42)
	var a3: Dictionary = PetIndividuality.roll_aptitudes(pet, 43)
	assert_int(int(a1.atk)).is_equal(int(a2.atk))
	assert_int(int(a1.def)).is_equal(int(a2.def))
	assert_bool(JSON.stringify(a1) == JSON.stringify(a3)).is_false()
	assert_int(int(a1.atk)).is_between(int(pet.aptitudes[0]), int(pet.aptitudes[1]))
	assert_int(int(a1.def)).is_between(int(pet.aptitudes[2]), int(pet.aptitudes[3]))
	assert_int(int(a1.hp)).is_between(int(pet.aptitudes[4]), int(pet.aptitudes[5]))
	assert_int(int(a1.spd)).is_between(int(pet.aptitudes[6]), int(pet.aptitudes[7]))
	assert_int(int(a1.mag)).is_between(int(pet.aptitudes[8]), int(pet.aptitudes[9]))


## 性格 roll：同种子确定，从池中选
func test_nature_roll_from_pool() -> void:
	var pet := _pet(1001)
	var pool: Array = PetIndividuality._as_array(pet.natures)
	var n1: String = PetIndividuality.roll_nature(pet, 42)
	var n2: String = PetIndividuality.roll_nature(pet, 42)
	assert_str(n1).is_equal(n2)
	assert_bool(pool.has(n1)).is_true()


## 性格修正表
func test_nature_modifiers() -> void:
	var m1: Dictionary = PetIndividuality.nature_modifiers("沉稳")
	assert_float(float(m1.def)).is_equal_approx(0.05, 0.001)
	assert_float(float(m1.spd)).is_equal_approx(-0.03, 0.001)
	var m2: Dictionary = PetIndividuality.nature_modifiers("未知")
	assert_int(m2.size()).is_equal(0)


## 突破消耗：等级门槛与修为递增
func test_breakthrough_cost_escalates() -> void:
	var pet := _pet(1001)
	var c1: Dictionary = PetIndividuality.breakthrough_cost(pet, 0, _g)
	assert_bool(bool(c1.can)).is_true()
	assert_int(int(c1.requiredLevel)).is_equal(int(_g.BRK_LV2))
	assert_int(int(c1.xiuCost)).is_greater(0)
	var c2: Dictionary = PetIndividuality.breakthrough_cost(pet, 1, _g)
	assert_int(int(c2.requiredLevel)).is_equal(int(_g.BRK_LV3))
	assert_int(int(c2.xiuCost)).is_greater(int(c1.xiuCost))
	var c5: Dictionary = PetIndividuality.breakthrough_cost(pet, 4, _g)
	assert_bool(bool(c5.can)).is_false()


## 突破阶段名从链中取
func test_breakthrough_stage_name() -> void:
	var pet := _pet(1001)
	var chain: Array = PetIndividuality._as_array(pet.breaks)
	var c: Dictionary = PetIndividuality.breakthrough_cost(pet, 0, _g)
	assert_str(String(c.stageName)).is_equal(String(chain[1]))
