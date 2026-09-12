## doc: 15 §4
## UTC 时间切片测试——黄金用例与 TS 基准 tests/timeSlicer.test.ts 同字面量。
extends GdUnitTestSuite

const EPOCH: int = 0


func test_season_index_and_cycle() -> void:
	assert_int(UtcTimeSlicer.season_index(-100, EPOCH)).is_equal(0)
	assert_int(UtcTimeSlicer.season_index(0, EPOCH)).is_equal(0)
	assert_int(UtcTimeSlicer.season_index(431999, EPOCH)).is_equal(0)
	assert_int(UtcTimeSlicer.season_index(432000, EPOCH)).is_equal(1)
	assert_int(UtcTimeSlicer.season_of_year(432000, EPOCH)).is_equal(1)
	assert_int(UtcTimeSlicer.season_of_year(4 * 432000 + 5, EPOCH)).is_equal(0)


func test_boundaries() -> void:
	assert_int(UtcTimeSlicer.next_tick_boundary(0, EPOCH)).is_equal(300)
	assert_int(UtcTimeSlicer.next_tick_boundary(300, EPOCH)).is_equal(600)
	assert_int(UtcTimeSlicer.next_tick_boundary(299, EPOCH)).is_equal(300)
	assert_int(UtcTimeSlicer.next_season_boundary(-100, EPOCH)).is_equal(0)
	assert_int(UtcTimeSlicer.next_season_boundary(431900, EPOCH)).is_equal(432000)
	assert_int(UtcTimeSlicer.next_season_boundary(432000, EPOCH)).is_equal(864000)


func test_slice_range_basic_ticks() -> void:
	var slices: Array = UtcTimeSlicer.slice_range(0, 600, EPOCH)
	assert_int(slices.size()).is_equal(2)
	assert_int(slices[0].start).is_equal(0)
	assert_int(slices[0].end).is_equal(300)
	assert_int(slices[1].end).is_equal(600)


func test_slice_range_cross_season() -> void:
	var slices: Array = UtcTimeSlicer.slice_range(431900, 432400, EPOCH)
	assert_int(slices.size()).is_equal(3)
	assert_int(slices[0].end).is_equal(432000)
	assert_int(slices[0].season).is_equal(0)
	assert_int(slices[1].start).is_equal(432000)
	assert_int(slices[1].season).is_equal(1)
	assert_int(slices[1].end).is_equal(432300)
	assert_int(slices[2].end).is_equal(432400)


func test_slice_range_invalid_and_exact() -> void:
	assert_int(UtcTimeSlicer.slice_range(600, 600, EPOCH).size()).is_equal(0)
	assert_int(UtcTimeSlicer.slice_range(700, 600, EPOCH).size()).is_equal(0)
	assert_int(UtcTimeSlicer.slice_range(300, 600, EPOCH).size()).is_equal(1)
	assert_int(UtcTimeSlicer.slice_range(300, 600, EPOCH)[0].start).is_equal(300)


func test_slice_range_epoch_offset() -> void:
	# 纪元非零：切片边界相对纪元对齐（700s 跨 3 个 tick 段）
	var epoch := 1000
	var slices: Array = UtcTimeSlicer.slice_range(1000, 1700, epoch)
	assert_int(slices.size()).is_equal(3)
	assert_int(slices[0].end).is_equal(1300)
	assert_int(slices[1].end).is_equal(1600)
	assert_int(slices[2].end).is_equal(1700)
	assert_int(UtcTimeSlicer.season_of_year(999, epoch)).is_equal(0)
	assert_int(UtcTimeSlicer.next_tick_boundary(999, epoch)).is_equal(1000)
