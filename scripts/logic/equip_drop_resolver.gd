## doc: 08 M3 Phase 0 契约 / 14 R-P1-02
## 装备掉落 resolver——纯逻辑（RefCounted），与 TS 基准 src/equipment/drop.ts 逐行对齐。
## 生成顺序：品质（自然 roll → 保底覆盖）→ 模板 → 装备等级 → 词条数 → 无放回选择 → 词条值。
## Phase 0 口径：dropCount=guaranteed attempts；pityUnit=settlement；quality 持久化为实例结果；
## 橙红威能延期（已知缺口）；Save 原子提交集成随 M4 落地，本类不做 IO。
class_name EquipDropResolver
extends RefCounted


static func empty_pity_state() -> Dictionary:
	return {"schemaVersion": 1, "counters": {}}


## 幸运值（08 §3）：稀有档（rareForLuck）×(1+luck/1000)
static func apply_luck(rule: Dictionary, qualities: Dictionary, luck: float) -> Array:
	var out: Array = []
	var weights: Array = rule.weights
	for q in range(weights.size()):
		var w := float(weights[q])
		var row: Dictionary = qualities.get(q, {})
		if bool(rule.luckApply) and not row.is_empty() and bool(row.rareForLuck):
			w *= 1.0 + luck / 1000.0
		out.append(w)
	return out


static func _clone_pity(state: Dictionary) -> Dictionary:
	var counters := {}
	for k in state.counters:
		counters[k] = state.counters[k]
	return {"schemaVersion": int(state.schemaVersion), "counters": counters}


## 词条展开：掉落与鉴定共用（鉴定幂等的依据）
static func _expand_affixes(
	item_seed: int, quality: int, level: int, ec: Dictionary, g: Dictionary
) -> Dictionary:
	var q_row: Dictionary = ec.qualities.get(quality, {})
	if q_row.is_empty():
		return {"affixes": [], "error": "未知品质 %d" % quality}
	var span := int(q_row.affixMax) - int(q_row.affixMin) + 1
	var ones: Array = []
	ones.resize(span)
	ones.fill(1)
	var count_rng := EquipDropRng.make_stream(
		EquipDropRng.derive_stream_seed(item_seed, EquipDropRng.TAG_AFFIX_COUNT)
	)
	var count := int(q_row.affixMin) + EquipDropRng.roll_weighted_index(ones, count_rng)
	if count <= 0:
		return {"affixes": [], "error": ""}

	var candidates: Array = []
	for a in ec.affixes:
		if quality >= int(a.qualityMin) and quality <= int(a.qualityMax):
			candidates.append(a)
	var select_rng := EquipDropRng.make_stream(
		EquipDropRng.derive_stream_seed(item_seed, EquipDropRng.TAG_AFFIX_SELECT)
	)
	var value_rng := EquipDropRng.make_stream(
		EquipDropRng.derive_stream_seed(item_seed, EquipDropRng.TAG_AFFIX_VALUE)
	)
	var picked_stats := {}
	var affixes: Array = []
	var picked_rows: Array = []
	for i in range(count):
		var pool: Array = []
		for a in candidates:
			if not picked_stats.has(String(a.stat)):
				pool.append(a)
		if pool.is_empty():
			return {"affixes": [], "error": "品质 %d 需 %d 条不同词条，候选不足" % [quality, count]}
		var pool_weights: Array = []
		for a in pool:
			pool_weights.append(float(a.weight))
		var affix: Dictionary = pool[EquipDropRng.roll_weighted_index(pool_weights, select_rng)]
		picked_rows.append(affix)
		picked_stats[String(affix.stat)] = true
	for a in picked_rows:
		var v := (
			(float(a.min) + value_rng.next() * (float(a.max) - float(a.min)))
			* (1.0 + float(level) * float(g.EQUIP_AFFIX_LV_SCALE))
		)
		(
			affixes
			. append(
				{
					"affixId": int(a.affixId),
					"stat": String(a.stat),
					"rollType": int(a.rollType),
					"valueMicro": roundi(v * 1000000.0),
				}
			)
		)
	return {"affixes": affixes, "error": ""}


static func resolve_settlement(request: Dictionary, ec: Dictionary, g: Dictionary) -> Dictionary:
	var seq := int(request.settlementSeq)
	var drop_id := int(request.dropId)
	var fail := func(error: String) -> Dictionary:
		return {
			"settlementSeq": seq,
			"dropId": drop_id,
			"items": [],
			"pityBefore": _clone_pity(request.pityState),
			"pityAfter": _clone_pity(request.pityState),
			"pityTriggered": false,
			"error": error,
			"canonicalLog": [],
		}
	var rule: Dictionary = ec.rules.get(drop_id, {})
	if rule.is_empty():
		return fail.call("未知 dropId=%d" % drop_id)
	var drop_count := int(request.dropCount)
	if drop_count < 1 or drop_count > 99:
		return fail.call("dropCount 必须在 1..99")
	var monster_level := int(request.monsterLevel)
	if monster_level < 1:
		return fail.call("monsterLevel 必须 >= 1")
	var luck := float(request.luckValue)
	if luck < 0.0:
		return fail.call("luckValue 必须 >= 0")

	var settle_seed := EquipDropRng.derive_settlement_seed(int(request.rootSeed), seq, drop_id)
	var adjusted := apply_luck(rule, ec.qualities, luck)

	# ① 品质自然 roll（保底覆盖不删除自然结果，流序稳定）
	var qualities: Array = []
	for i in range(drop_count):
		var item_seed := EquipDropRng.derive_item_seed(settle_seed, i)
		var qr := EquipDropRng.make_stream(
			EquipDropRng.derive_stream_seed(item_seed, EquipDropRng.TAG_QUALITY)
		)
		qualities.append(EquipDropRng.roll_weighted_index(adjusted, qr))

	# ② 保底（settlement 语义：一次结算至多推进一格）
	var pity_before := _clone_pity(request.pityState)
	var pity_after := _clone_pity(request.pityState)
	var pity_triggered := false
	var counter_key := str(drop_id)
	var before := int(pity_before.counters.get(counter_key, 0))
	if (
		int(rule.pityQuality) > 0
		and int(rule.pityCount) > 0
		and String(rule.pityUnit) == "settlement"
		and drop_count > 0
	):
		var natural := false
		for q in qualities:
			if int(q) >= int(rule.pityQuality):
				natural = true
				break
		if natural:
			pity_after.counters[counter_key] = 0
		elif before + 1 >= int(rule.pityCount):
			var ones: Array = []
			ones.resize(drop_count)
			ones.fill(1)
			var pity_rng := EquipDropRng.make_stream(
				EquipDropRng.derive_stream_seed(settle_seed, EquipDropRng.TAG_PITY_INDEX)
			)
			var forced := EquipDropRng.roll_weighted_index(ones, pity_rng)
			qualities[forced] = int(rule.pityQuality)
			pity_after.counters[counter_key] = 0
			pity_triggered = true
		else:
			pity_after.counters[counter_key] = before + 1

	# ③ 模板 / 等级 / 词条
	var items: Array = []
	var log: Array[String] = [
		(
			"[loot] seed=%d seq=%d dropId=%d count=%d pityBefore=%d pityAfter=%d pityTriggered=%d"
			% [
				int(request.rootSeed) & 0xFFFFFFFF,
				seq,
				drop_id,
				drop_count,
				before,
				int(pity_after.counters.get(counter_key, 0)),
				1 if pity_triggered else 0,
			]
		)
	]
	var equip_weights: Array = []
	for e in ec.equipBase:
		equip_weights.append(float(e.weight))
	for i in range(drop_count):
		var item_seed := EquipDropRng.derive_item_seed(settle_seed, i)
		var quality := int(qualities[i])
		var q_row: Dictionary = ec.qualities.get(quality, {})
		if q_row.is_empty():
			return fail.call("品质 %d 无 EquipQuality 配置" % quality)

		var template_rng := EquipDropRng.make_stream(
			EquipDropRng.derive_stream_seed(item_seed, EquipDropRng.TAG_TEMPLATE)
		)
		var template: Dictionary = ec.equipBase[EquipDropRng.roll_weighted_index(
			equip_weights, template_rng
		)]

		if String(rule.equipLvMode) != "monster_level":
			return fail.call("Phase 0 不支持 equipLvMode=%s" % String(rule.equipLvMode))
		var offset_span := int(rule.equipLvOffsetMax) - int(rule.equipLvOffsetMin) + 1
		var span_ones: Array = []
		span_ones.resize(offset_span)
		span_ones.fill(1)
		var level_rng := EquipDropRng.make_stream(
			EquipDropRng.derive_stream_seed(item_seed, EquipDropRng.TAG_LEVEL)
		)
		var offset := (
			int(rule.equipLvOffsetMin) + EquipDropRng.roll_weighted_index(span_ones, level_rng)
		)
		var level := maxi(int(g.EQUIP_LEVEL_MIN), monster_level + offset)

		var expand := _expand_affixes(item_seed, quality, level, ec, g)
		if String(expand.error) != "":
			return fail.call(String(expand.error))
		var affixes: Array = expand.affixes
		var instance_id := "%d-%d" % [seq, i]
		(
			items
			. append(
				{
					"instanceId": instance_id,
					"equipId": int(template.equipId),
					"quality": quality,
					"level": level,
					"rollSeed": item_seed,
					"identified": not bool(q_row.unidentified),
					"affixes": affixes,
				}
			)
		)
		var item_fmt := (
			"[loot_item] index=%d instanceId=%s equipId=%d quality=%d level=%d identified=%d "
			+ "rollSeed=%d affixCount=%d"
		)
		var item_line: String = (
			item_fmt
			% [
				i,
				instance_id,
				int(template.equipId),
				quality,
				level,
				0 if bool(q_row.unidentified) else 1,
				item_seed & 0xFFFFFFFF,
				affixes.size(),
			]
		)
		log.append(item_line)
		for j in range(affixes.size()):
			var a: Dictionary = affixes[j]
			log.append(
				(
					"[loot_affix] item=%d order=%d affixId=%d valueMicro=%d"
					% [i, j, int(a.affixId), int(a.valueMicro)]
				)
			)
	log.append("[loot_end] items=%d applied=0" % items.size())
	return {
		"settlementSeq": seq,
		"dropId": drop_id,
		"items": items,
		"pityBefore": pity_before,
		"pityAfter": pity_after,
		"pityTriggered": pity_triggered,
		"error": "",
		"canonicalLog": log,
	}


## 鉴定：按实例已存 rollSeed 重展开，幂等且不消耗任何正式随机流
static func resolve_identification(inst: Dictionary, ec: Dictionary, g: Dictionary) -> Dictionary:
	var template: Dictionary = {}
	for e in ec.equipBase:
		if int(e.equipId) == int(inst.equipId):
			template = e
			break
	if template.is_empty():
		return {"error": "未知 equipId=%d" % int(inst.equipId)}
	var expand := _expand_affixes(int(inst.rollSeed), int(inst.quality), int(inst.level), ec, g)
	if String(expand.error) != "":
		return {"error": String(expand.error)}
	var main_value := (
		float(template.baseValue) * (1.0 + float(inst.level) * float(g.EQUIP_MAIN_LV_SCALE))
	)
	return {
		"instanceId": String(inst.instanceId),
		"equipId": int(inst.equipId),
		"slot": int(template.slot),
		"mainStat": String(template.mainStat),
		"mainValueMicro": roundi(main_value * 1000000.0),
		"quality": int(inst.quality),
		"level": int(inst.level),
		"identified": bool(inst.identified),
		"affixes": expand.affixes,
		"error": "",
	}
