## doc: 08 §4/§5（主属性/词条）/ §7（强化/套装）
## 穿戴装备 → 属性修正管线（GDScript）——与 TS 基准 src/logic/equipStats.ts 逐位一致。
## 纯函数：按穿戴上装展开 主属性+词条（rollType 1 百分比/2 平面）×强化倍率，
## 套装 2/3 件激活——六维属性键进 ratio，特殊机制键（dmg_* 等）只列出（战斗消费待引擎扩展）。
class_name EquipStats
extends RefCounted

const BASIC_STATS := ["hp", "atk", "def", "spd", "mag", "res"]


## 穿戴修正：pet.equips 为 {slot(int): instanceId(String)}；返回 {flat, ratio, activeSets, special}
## flat=六维平面加成（引擎 statMods 通道）；ratio=比例修正（并入 natureMods 偏移通道）
static func equipped_mods(
	pet: Dictionary, items: Array, ec: Dictionary, set_rows: Array, g: Dictionary
) -> Dictionary:
	var flat := {}
	var ratio := {}
	var active_sets: Array = []
	var special: Array = []
	var worn_set_ids: Array = []
	var equips: Dictionary = pet.get("equips", {})
	for slot in equips:
		var instance_id := String(equips[slot])
		var item: Dictionary = {}
		for it in items:
			if String(it.instanceId) == instance_id:
				item = it
				break
		if item.is_empty() or not bool(item.identified):
			continue
		var view: Dictionary = EquipDropResolver.resolve_identification(item, ec, g)
		if String(view.error) != "":
			continue
		var mult: float = EquipEnhance.enhance_multiplier(int(item.get("enhanceLevel", 0)))
		flat[String(view.mainStat)] = (
			int(flat.get(String(view.mainStat), 0))
			+ roundi(float(view.mainValueMicro) / 1000000.0 * mult)
		)
		for affix in view.affixes:
			var value: float = float(affix.valueMicro) / 1000000.0 * mult
			if int(affix.rollType) == 2:
				flat[String(affix.stat)] = int(flat.get(String(affix.stat), 0)) + roundi(value)
			else:
				ratio[String(affix.stat)] = float(ratio.get(String(affix.stat), 0.0)) + value
		for e in ec.equipBase:
			if int(e.equipId) == int(item.equipId):
				worn_set_ids.append(int(e.setId))
				break
	# 套装：2/3 件激活（EquipEnhance.active_set_bonus 同源）
	var active: Dictionary = EquipEnhance.active_set_bonus(worn_set_ids)
	for sid in active:
		var row: Dictionary = {}
		for s in set_rows:
			if int(s.equipSetId) == int(sid):
				row = s
				break
		if row.is_empty():
			continue
		var tier := int(active[sid].tier)
		active_sets.append({"id": int(sid), "name": String(row.name), "tier": tier})
		# 3 件 = 2 件 + 3 件效果叠加（docs/08 §7）
		for tier_i in [2, 3]:
			if tier < tier_i:
				continue
			var stat := String(row.bonus2Stat if tier_i == 2 else row.bonus3Stat)
			var pct: float = float(row.bonus2Pct if tier_i == 2 else row.bonus3Pct)
			var desc := String(row.bonus2Desc if tier_i == 2 else row.bonus3Desc)
			if BASIC_STATS.has(stat):
				ratio[stat] = float(ratio.get(stat, 0.0)) + pct
			else:
				# 特殊机制键（dmg_first/cd_reduce 等）战斗消费待引擎扩展，先登记
				special.append("%s(%d件)：%s" % [String(row.name), tier_i, desc])
	return {"flat": flat, "ratio": ratio, "activeSets": active_sets, "special": special}
