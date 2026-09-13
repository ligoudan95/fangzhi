## doc: 15 §2.4 / 26 §3
## 库存账本（GDScript 镜像）——与 TS 基准 src/logic/inventoryLedger.ts 逐位一致。
## 确定性红线：衰减先按数量比例 floor 分摊、余数按 itemId 升序补齐。
class_name InventoryLedger
extends RefCounted


## 软容量入库：可超上限保留；cap_mult 为仓库建筑倍率（默认 1.0）；
## 返回 {stacks, added, stored, cap, overflow}（不修改输入）
static func add_item(
	stacks: Array,
	item_id: int,
	amount: int,
	category_of: Dictionary,
	rules: Dictionary,
	cap_mult: float = 1.0
) -> Dictionary:
	if amount < 0:
		return {"error": "amount 不能为负"}
	if not category_of.has(item_id):
		return {"error": "物品 %d 无仓储分类" % item_id}
	var category := int(category_of[item_id])
	if not rules.has(category):
		return {"error": "仓储分类 %d 无容量规则" % category}
	var cap := int(float(int(rules[category])) * cap_mult)
	var next: Array = []
	for s in stacks:
		next.append({"itemId": int(s.itemId), "amount": int(s.amount)})
	var before := 0
	var existing: Dictionary = {}
	for s in next:
		if int(s.itemId) == item_id:
			existing = s
			before = int(s.amount)
			break
	if not existing.is_empty():
		existing.amount = before + amount
	else:
		next.append({"itemId": item_id, "amount": amount})
	next.sort_custom(_item_id_cmp)
	var stored := before + amount
	return {
		"stacks": next,
		"added": amount,
		"stored": stored,
		"cap": cap,
		"overflow": maxi(0, stored - cap),
		"error": "",
	}


static func _item_id_cmp(a: Dictionary, b: Dictionary) -> bool:
	return int(a.itemId) < int(b.itemId)


## 周期复合后的剩余超额：每周期对当前超额扣 pct（不足 1 按 1 计）
static func _remaining_overflow(total: int, cap: int, periods: int, pct: float) -> int:
	var target := total - cap
	var i := 0
	while i < periods and target > 0:
		var step := int(floorf(float(target) * pct))
		if step > 0:
			target -= step
		else:
			target -= 1
		i += 1
	return maxi(0, target)


## 溢出衰减（15 §2.4）：仅当分类总量超软上限时对超额部分按周期复合扣减；
## 分摊：每堆 floor(堆量/总量 × 衰减量)，余数按 itemId 升序补齐（不超过堆量）。
static func apply_overflow_decay(
	stacks: Array, category_items: Array, cap: int, periods: int, pct: float
) -> Dictionary:
	var next: Array = []
	for s in stacks:
		next.append({"itemId": int(s.itemId), "amount": int(s.amount)})
	var cat: Array = []
	for s in next:
		if category_items.has(int(s.itemId)):
			cat.append(s)
	cat.sort_custom(_item_id_cmp)
	var total := 0
	for s in cat:
		total += int(s.amount)
	if periods <= 0 or pct <= 0.0 or total <= cap:
		return {"stacks": next, "decayed": 0}
	var decay_total: int = mini(
		(total - cap) - _remaining_overflow(total, cap, periods, pct), total
	)
	var assigned := 0
	var floors: Array[int] = []
	for s in cat:
		var f := int(floorf(float(s.amount) / float(total) * float(decay_total)))
		floors.append(f)
		assigned += f
	var remainder := decay_total - assigned
	for i in range(cat.size()):
		if remainder <= 0:
			break
		var can_take: int = mini(remainder, int(cat[i].amount) - floors[i])
		floors[i] += can_take
		remainder -= can_take
	for i in range(cat.size()):
		cat[i].amount = int(cat[i].amount) - floors[i]
	var kept: Array = []
	for s in next:
		if int(s.amount) > 0:
			kept.append(s)
	return {"stacks": kept, "decayed": decay_total}
