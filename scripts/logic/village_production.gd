## doc: 15 §2 / 26 §3
## 村落生产结算（GDScript 镜像）——与 TS 基准 src/logic/villageProduction.ts 逐行对齐。
## 纯函数：成熟田块一次性收获后清空；不原地改输入；幂等。
class_name VillageProduction
extends RefCounted


## 结算窗口 [cursor, min(now, cursor+cap))（15 §2.1/§2.2）；季节系数按成熟点所在切片。
## 溢出衰减：窗口内每满 STORAGE_DECAY_PERIOD_SEC 对超软上限分类扣 pct（§2.4）。
static func settle_crops(
	fields: Array, cursor: int, now: int, inventory: Array, config: Dictionary
) -> Dictionary:
	if now <= cursor:
		return {
			"nextFields": _copy_fields(fields),
			"nextCursor": cursor,
			"outputs": [],
			"cappedBy": 0,
			"inventory": _copy_stacks(inventory),
		}
	var capped_now: int = mini(now, cursor + int(config.g.OFFLINE_CAP_BASE_SEC))
	var capped_by: int = now - capped_now
	var slices: Array = UtcTimeSlicer.slice_range(
		cursor, capped_now, int(config.g.SEASON_EPOCH_UTC_SEC)
	)
	var outputs: Array = []
	var harvested := {}
	var inv := _copy_stacks(inventory)
	for slice in slices:
		var season := UtcTimeSlicer.season_of_year(
			int(slice.start), int(config.g.SEASON_EPOCH_UTC_SEC)
		)
		var farm_mult := 1.0
		if config.seasons.has(season):
			farm_mult = float(config.seasons[season].farmMult)
		for field in fields:
			if harvested.has(int(field.slotId)):
				continue
			if not config.crops.has(int(field.cropId)):
				continue
			var crop: Dictionary = config.crops[int(field.cropId)]
			var mature_at: int = int(field.startedAtUtcSec) + int(crop.growMin) * 60
			if mature_at <= int(slice.start) or mature_at > int(slice.end):
				continue
			var amount: int = roundi(float(crop.outputCount) * farm_mult)
			if amount > 0:
				var res := InventoryLedger.add_item(
					inv, int(crop.outputItemId), amount, config.categoryOf, config.storageRules
				)
				if String(res.error) != "":
					return {"error": String(res.error)}
				inv = res.stacks
				outputs.append(
					{"itemId": int(crop.outputItemId), "amount": amount, "season": season}
				)
			harvested[int(field.slotId)] = true
	var next_fields: Array = []
	for field in fields:
		if not harvested.has(int(field.slotId)):
			next_fields.append(
				{
					"slotId": int(field.slotId),
					"cropId": int(field.cropId),
					"startedAtUtcSec": int(field.startedAtUtcSec)
				}
			)
	var periods: int = int(float(capped_now - cursor) / float(config.g.STORAGE_DECAY_PERIOD_SEC))
	if periods > 0:
		for category in config.storageRules:
			var items: Array = []
			for item_id in config.categoryOf:
				if int(config.categoryOf[item_id]) == int(category):
					items.append(int(item_id))
			var decayed := InventoryLedger.apply_overflow_decay(
				inv,
				items,
				int(config.storageRules[category]),
				periods,
				float(config.g.STORAGE_DECAY_PCT)
			)
			inv = decayed.stacks
	return {
		"nextFields": next_fields,
		"nextCursor": now,
		"outputs": outputs,
		"cappedBy": capped_by,
		"inventory": inv,
	}


static func _copy_fields(fields: Array) -> Array:
	var out: Array = []
	for f in fields:
		out.append(
			{
				"slotId": int(f.slotId),
				"cropId": int(f.cropId),
				"startedAtUtcSec": int(f.startedAtUtcSec)
			}
		)
	return out


static func _copy_stacks(stacks: Array) -> Array:
	var out: Array = []
	for s in stacks:
		out.append({"itemId": int(s.itemId), "amount": int(s.amount)})
	return out
