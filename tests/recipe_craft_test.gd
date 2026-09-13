## doc: 05 §7（锻造/药庐生产链）/ 26 §4.2
## 配方生产测试——与 tests/recipeCraft.test.ts 同口径
extends GdUnitTestSuite

const RECIPES := {
	4:
	{
		"recipeId": 4,
		"station": 1,
		"inputs": "201:2;206:2",
		"outputItemId": 206,
		"outputCount": 1,
		"durationMin": 30
	},
	1:
	{
		"recipeId": 1,
		"station": 2,
		"inputs": "101:3",
		"outputItemId": 107,
		"outputCount": 1,
		"durationMin": 10
	},
}
const CATEGORY_OF := {101: 3, 107: 3, 201: 1, 206: 5}
const RULES := {1: 200, 3: 100, 5: 50}


func _recipe_of(recipe_id: int) -> Dictionary:
	return RECIPES.get(recipe_id, {})


func test_parse_inputs() -> void:
	var pairs: Array = RecipeCraft.parse_inputs("201:2;206:2")
	assert_int(pairs.size()).is_equal(2)
	assert_int(int(pairs[0].itemId)).is_equal(201)
	assert_int(int(pairs[0].count)).is_equal(2)
	assert_int(RecipeCraft.parse_inputs("").size()).is_equal(0)
	# 非法段跳过：非数字/0/负数
	assert_int(RecipeCraft.parse_inputs("a:b;0:1;201:0;201:-1;301:2").size()).is_equal(1)


func test_start_craft() -> void:
	var inv: Array = [{"itemId": 201, "amount": 5}, {"itemId": 206, "amount": 2}]
	var r: Dictionary = RecipeCraft.start_craft([], 4, "201:2;206:2", 1000, inv, 2)
	assert_str(String(r.error)).is_empty()
	assert_int(r.jobs.size()).is_equal(1)
	assert_int(r.inventory.size()).is_equal(1)
	assert_int(int(r.inventory[0].itemId)).is_equal(201)
	assert_int(int(r.inventory[0].amount)).is_equal(3)
	# 缺料拒绝（206 已扣光）
	var r2: Dictionary = RecipeCraft.start_craft(r.jobs, 4, "201:2;206:2", 1100, r.inventory, 2)
	assert_str(String(r2.error)).is_equal("材料不足")
	# 队列满拒绝
	var full: Array = [
		{"recipeId": 1, "startedAtUtcSec": 0},
		{"recipeId": 1, "startedAtUtcSec": 1},
	]
	var r3: Dictionary = RecipeCraft.start_craft(full, 4, "201:2;206:2", 1200, inv, 2)
	assert_str(String(r3.error)).is_equal("队列已满")


func test_settle_crafts() -> void:
	var jobs: Array = [{"recipeId": 4, "startedAtUtcSec": 0}]
	var callable := Callable(self, "_recipe_of")
	# 未到期保留
	var half: Dictionary = RecipeCraft.settle_crafts(
		jobs, 29 * 60, [], callable, CATEGORY_OF, RULES, 1.0
	)
	assert_int(half.nextJobs.size()).is_equal(1)
	assert_int(half.outputs.size()).is_equal(0)
	# 到时产出并移除
	var done: Dictionary = RecipeCraft.settle_crafts(
		jobs, 30 * 60, [], callable, CATEGORY_OF, RULES, 1.0
	)
	assert_int(done.nextJobs.size()).is_equal(0)
	assert_int(done.outputs.size()).is_equal(1)
	assert_int(int(done.outputs[0].itemId)).is_equal(206)
	assert_int(done.inventory.size()).is_equal(1)
	assert_int(int(done.inventory[0].amount)).is_equal(1)
	# 幂等：无重复产出
	var again: Dictionary = RecipeCraft.settle_crafts(
		done.nextJobs, 99999, done.inventory, callable, CATEGORY_OF, RULES, 1.0
	)
	assert_int(again.outputs.size()).is_equal(0)


func test_warehouse_cap_mult() -> void:
	var inv: Array = [{"itemId": 107, "amount": 95}]
	var r: Dictionary = RecipeCraft.settle_crafts(
		[{"recipeId": 1, "startedAtUtcSec": 0}],
		600,
		inv,
		Callable(self, "_recipe_of"),
		CATEGORY_OF,
		RULES,
		1.5
	)
	assert_int(r.outputs.size()).is_equal(1)
	assert_int(int(r.inventory[0].amount)).is_equal(96)
