## doc: 05 §4 / 26 §4.4——与 TS 基准 tests/petDispatch.test.ts 同口径
extends GdUnitTestSuite


func test_can_dispatch_min_stamina() -> void:
	(
		assert_bool(PetDispatch.can_dispatch({"staminaMilli": 100000, "moodMilli": 100000}, {}))
		. is_true()
	)
	(
		assert_bool(PetDispatch.can_dispatch({"staminaMilli": 15000, "moodMilli": 100000}, {}))
		. is_false()
	)


func test_dispatch_efficiency() -> void:
	var full: float = PetDispatch.dispatch_efficiency(
		{"staminaMilli": 100000, "moodMilli": 100000}, 0.0, {}
	)
	var low: float = PetDispatch.dispatch_efficiency(
		{"staminaMilli": 20000, "moodMilli": 100000}, 0.0, {}
	)
	assert_float(full).is_greater(0.95)
	assert_float(low).is_less(full)
	var boosted: float = PetDispatch.dispatch_efficiency(
		{"staminaMilli": 100000, "moodMilli": 100000}, 0.5, {}
	)
	assert_float(boosted).is_greater(full)


func test_settle_dispatch_drain() -> void:
	var r: Dictionary = PetDispatch.settle_dispatch(
		{"staminaMilli": 50000, "moodMilli": 80000}, 2.5, {}
	)
	assert_int(int(r.staminaMilli)).is_equal(25000)
	assert_int(int(r.moodMilli)).is_equal(67500)


func test_settle_rest_regen() -> void:
	var r: Dictionary = PetDispatch.settle_rest({"staminaMilli": 0, "moodMilli": 0}, 2.0, 1, {})
	assert_int(int(r.staminaMilli)).is_greater(0)
	assert_int(int(r.moodMilli)).is_greater(0)
	var full: Dictionary = PetDispatch.settle_rest(
		{"staminaMilli": 99000, "moodMilli": 99000}, 10.0, 5, {}
	)
	assert_int(int(full.staminaMilli)).is_less_equal(100000)
	assert_int(int(full.moodMilli)).is_less_equal(100000)


func test_idempotent() -> void:
	var c := {"staminaMilli": 50000, "moodMilli": 50000}
	var a: Dictionary = PetDispatch.settle_dispatch(c, 1.0, {})
	var b: Dictionary = PetDispatch.settle_dispatch(c, 1.0, {})
	assert_int(int(a.staminaMilli)).is_equal(int(b.staminaMilli))
