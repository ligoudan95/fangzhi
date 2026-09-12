## doc: 26 §4.3（矿场）/ 05 §6
## 矿场结算（GDScript 镜像）——与 TS 基准 src/logic/mineProduction.ts 逐行对齐。
## 纯函数：切片×季节系数，小时折算产量（分数跨切片结转）；物品入软容量库存，灵晶进钱包。
class_name MineProduction
extends RefCounted


## 结算窗口 [cursor, min(now, cursor+cap))；分数产出余数结转（300s 切片内 rate×hours<1 防 floor 清零）
static func settle_mines(
	jobs: Array, cursor: int, now: int, wallet: Dictionary, inventory: Array, config: Dictionary
) -> Dictionary:
	if now <= cursor:
		return {
			"nextJobs": jobs.duplicate(true),
			"nextCursor": cursor,
			"wallet": wallet.duplicate(true),
			"inventory": inventory.duplicate(true),
			"outputs": [],
		}
	var capped_now: int = mini(now, cursor + int(config.g.OFFLINE_CAP_BASE_SEC))
	var slices: Array = UtcTimeSlicer.slice_range(
		cursor, capped_now, int(config.g.SEASON_EPOCH_UTC_SEC)
	)
	var inv := []
	for s in inventory:
		inv.append({"itemId": int(s.itemId), "amount": int(s.amount)})
	var wal := {
		"beastShell": int(wallet.beastShell),
		"spiritCrystal": int(wallet.spiritCrystal),
		"totemEmblem": int(wallet.totemEmblem),
	}
	var outputs: Array = []
	var pending := {}
	for slice in slices:
		var season := UtcTimeSlicer.season_of_year(
			int(slice.start), int(config.g.SEASON_EPOCH_UTC_SEC)
		)
		var mult := 1.0
		if config.seasons.has(season):
			mult = float(config.seasons[season].mineMult)
		var hours: float = float(int(slice.end) - int(slice.start)) / 3600.0
		for job in jobs:
			if not config.mines.has(int(job.mineId)):
				continue
			var mine: Dictionary = config.mines[int(job.mineId)]
			var slot_id := int(job.slotId)
			var produce_fn := func(key: String, item_id: int, rate: int, to_wallet: bool) -> void:
				if rate <= 0:
					return
				var exact: float = float(pending.get(key, 0.0)) + float(rate) * mult * hours
				var amount: int = int(floorf(exact + 0.000001))  # 浮点累积误差容差
				pending[key] = exact - float(amount)
				if amount <= 0:
					return
				if to_wallet:
					wal.spiritCrystal = int(wal.spiritCrystal) + amount
					outputs.append({"itemId": -1, "amount": amount})
					return
				if item_id <= 0:
					return
				var res := InventoryLedger.add_item(
					inv, item_id, amount, config.categoryOf, config.storageRules
				)
				if String(res.error) != "":
					return
				inv = res.stacks
				outputs.append({"itemId": item_id, "amount": amount})
			produce_fn.call("%d:iron" % slot_id, 201, int(mine.ironRate), false)
			produce_fn.call("%d:crystal" % slot_id, 202, int(mine.crystalRate), false)
			produce_fn.call("%d:refined" % slot_id, 203, int(mine.refinedRate), false)
			produce_fn.call("%d:spirit" % slot_id, -1, int(mine.spiritRate), true)
	return {
		"nextJobs": jobs.duplicate(true),
		"nextCursor": now,
		"wallet": wal,
		"inventory": inv,
		"outputs": outputs,
	}
