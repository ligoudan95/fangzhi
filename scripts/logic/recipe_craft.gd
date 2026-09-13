## doc: 05 §7（锻造/药庐生产链）/ 26 §4.2
## 配方生产（GDScript）——与 TS 基准 src/logic/recipeCraft.ts 逐位一致。
## 纯函数：inputs 解析 → 队列容量校验 → 扣料入队 → 到时结算产出。
## 队列容量与仓库倍率由调用方按 BuildingEffects 注入（本模块不读表）。
class_name RecipeCraft
extends RefCounted


## 解析 "itemId:count;itemId:count"；非法段跳过
static func parse_inputs(raw: String) -> Array:
	var out: Array = []
	for seg in String(raw).split(";", false):
		var pair = String(seg).split(":", false)
		if pair.size() != 2:
			continue
		var item_id := int(pair[0])
		var count := int(pair[1])
		if item_id > 0 and count > 0:
			out.append({"itemId": item_id, "count": count})
	return out


## 开始生产：队列未满 + 库存足料 → 扣料入队；返回 {error, jobs, inventory}（不修改输入）
static func start_craft(
	jobs: Array, recipe_id: int, inputs_raw: String, now: int, inventory: Array, queue_cap: int
) -> Dictionary:
	var next_jobs := []
	for j in jobs:
		next_jobs.append({"recipeId": int(j.recipeId), "startedAtUtcSec": int(j.startedAtUtcSec)})
	if next_jobs.size() >= queue_cap:
		return {"error": "队列已满", "jobs": next_jobs, "inventory": inventory.duplicate(true)}
	var inv := []
	for s in inventory:
		inv.append({"itemId": int(s.itemId), "amount": int(s.amount)})
	var needs := parse_inputs(inputs_raw)
	for need in needs:
		var have := 0
		for s in inv:
			if int(s.itemId) == int(need.itemId):
				have = int(s.amount)
				break
		if have < int(need.count):
			return {"error": "材料不足", "jobs": next_jobs, "inventory": inv}
	for need in needs:
		for s in inv:
			if int(s.itemId) == int(need.itemId):
				s.amount = int(s.amount) - int(need.count)
				break
	var kept := []
	for s in inv:
		if int(s.amount) > 0:
			kept.append(s)
	next_jobs.append({"recipeId": recipe_id, "startedAtUtcSec": now})
	return {"error": "", "jobs": next_jobs, "inventory": kept}


## 结算：到时任务（elapsed ≥ durationMin×60）产出入库；未到期保留；返回 {nextJobs, outputs, inventory}
## recipe_of: Callable(recipe_id) -> 行 Dictionary（空字典视为无效任务并丢弃）
static func settle_crafts(
	jobs: Array,
	now: int,
	inventory: Array,
	recipe_of: Callable,
	category_of: Dictionary,
	rules: Dictionary,
	cap_mult: float
) -> Dictionary:
	var inv := []
	for s in inventory:
		inv.append({"itemId": int(s.itemId), "amount": int(s.amount)})
	var next_jobs: Array = []
	var outputs: Array = []
	for j in jobs:
		var row: Dictionary = recipe_of.call(int(j.recipeId))
		if row.is_empty():
			continue
		var duration_sec := int(row.durationMin) * 60
		if now - int(j.startedAtUtcSec) < duration_sec:
			next_jobs.append(
				{"recipeId": int(j.recipeId), "startedAtUtcSec": int(j.startedAtUtcSec)}
			)
			continue
		var out_id := int(row.outputItemId)
		var out_count := int(row.outputCount)
		if out_id > 0 and out_count > 0:
			var res := InventoryLedger.add_item(
				inv, out_id, out_count, category_of, rules, cap_mult
			)
			if String(res.error) == "":
				inv = res.stacks
				outputs.append({"itemId": out_id, "amount": out_count})
	return {"nextJobs": next_jobs, "outputs": outputs, "inventory": inv}
