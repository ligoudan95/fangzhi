# gdlint: disable=max-public-methods
# 会话编排器是垂直切片粘合层，公共方法数量属预期
## doc: 15 §3.5 / 16 §2 / 08 §12
## 垂直切片会话（View 层装配器）：读设备 UTC → 调 Config/Save/Logic；
## 写档成功才替换内存状态（docs/15 §3.5 单向流）。串联：
## 新档/读档 → 序章推进 → 战斗结算→任务 → 装备掉落→鉴定→任务 → 捕捉→任务
## → 播种/离线结算→收获→任务 → 存档往返。零业务规则：只做编排与事实搬运。
class_name GameSession
extends Node

const SAVE_SCRIPT: GDScript = preload("res://scripts/infra/save_service.gd")

## 序章演示三兽（docs/16）：阵伍为空时的出战回退
const FTUE_TEAM_IDS: Array = [[1001, 12, 900, 1], [1002, 12, 900, 1], [1005, 12, 950, 1]]

var data: Dictionary = {}
var settlement_seq: int = 0

var _save: Node
var _tables: Dictionary = {}
var _quests: Array = []
var _village_config: Dictionary = {}
var _equip_config: Dictionary = {}
var _battle_cfg: Dictionary = {}


func _init(save_service: Node = null, tables_dir: String = "res://resources/config/") -> void:
	_save = save_service if save_service != null else SAVE_SCRIPT.new()
	add_child(_save)
	_tables = BattleSetup.load_tables(tables_dir)
	_quests = _tables.get("MainQuest", [])
	_build_village_config()
	_equip_config = BattleSetup.build_equip_config(_tables)


func _build_village_config() -> void:
	var crops := {}
	for c in _tables.get("Crop", []):
		crops[int(c.cropId)] = {
			"cropId": int(c.cropId),
			"growMin": int(c.growMin),
			"yieldN": int(c.yieldN),
			"outputItemId": int(c.outputItemId),
			"outputCount": int(c.outputCount),
		}
	var seasons := {}
	for s in _tables.get("SeasonWeather", []):
		seasons[int(s.seasonId)] = {"farmMult": float(s.farmMult), "mineMult": float(s.mineMult)}
	var mines := {}
	for m in _tables.get("Mine", []):
		mines[int(m.mineId)] = m
	var category_of := {}
	for i in _tables.get("ItemBase", []):
		category_of[int(i.itemId)] = int(i.storageCategory)
	var rules := {}
	for r in _tables.get("StorageRule", []):
		rules[int(r.categoryId)] = int(r.baseCap)
	var g: Dictionary = _tables.get("GlobalConst", {})
	_village_config = {
		"crops": crops,
		"seasons": seasons,
		"mines": mines,
		"categoryOf": category_of,
		"storageRules": rules,
		"g": g,
	}


func _building_rows() -> Array:
	return _tables.get("Building", [])


## 图腾柱离线上限（docs/05 §2）：按建筑等级钳制生产结算窗口
func _offline_cap_sec() -> int:
	return BuildingEffects.offline_cap_sec(
		data.village.buildings, _building_rows(), _village_config.g
	)


## 生产用配置副本：离线上限按图腾柱覆写（不改 _village_config 原表）
func _village_config_capped() -> Dictionary:
	var cfg := _village_config.duplicate(true)
	cfg.g.OFFLINE_CAP_BASE_SEC = _offline_cap_sec()
	return cfg


# ---------- 会话生命周期 ----------


func new_game(now_utc: int, root_seed: int, slot: String = "auto") -> bool:
	data = GameStateFactory.create_new(now_utc, root_seed)
	var res: Dictionary = _save.save_slot(slot, data)
	return bool(res.ok)


func load_game(slot: String = "auto") -> bool:
	var res: Dictionary = _save.load_slot(slot)
	if not bool(res.ok):
		return false
	data = res.data
	settlement_seq = _max_settlement_seq()
	return true


func save_game(slot: String = "auto") -> bool:
	var res: Dictionary = _save.save_slot(slot, data)
	return bool(res.ok)


func _max_settlement_seq() -> int:
	var max_seq := 0
	for sid in data.equipment.appliedSettlementIds:
		max_seq = maxi(max_seq, int(sid))
	return max_seq


# ---------- 任务进度（引擎事实 → QuestTracker） ----------


func _quests_state() -> Dictionary:
	return data.player.get("quests", QuestTracker.create_state())


func _apply_quest(goal_type: int, target_id: int, amount: int) -> Array:
	var state := _quests_state()
	var res: Dictionary = QuestTracker.add_progress(state, goal_type, target_id, amount, _quests)
	data.player.quests = res.state
	data.player.cultivation = (
		int(data.player.cultivation) + int(res.state.claimedXiu) - int(state.claimedXiu)
	)
	return res.done


func advance_story() -> Array:
	var state := _quests_state()
	var res: Dictionary = QuestTracker.advance_story(state, _quests)
	data.player.quests = res.state
	data.player.cultivation = (
		int(data.player.cultivation) + int(res.state.claimedXiu) - int(state.claimedXiu)
	)
	return res.done


func on_stage_cleared(stage_id: int) -> Array:
	return _apply_quest(1, stage_id, 1)


func on_pet_captured(pet_id: int) -> Array:
	# 灵宠个体化（docs/04 §2/§3）：捕捉时 roll 资质+性格，存种子不存值
	var pet_row := {}
	for p in _tables.get("PetBase", []):
		if int(p.petId) == pet_id:
			pet_row = p
			break
	if not pet_row.is_empty():
		var root_seed := int(data.rng.rootSeed)
		var cap_count: int = data.pets.size() + 1
		var apt_seed := EquipDropRng.mix(root_seed ^ (pet_id * 31 + cap_count * 7))
		var nature_seed := EquipDropRng.mix(apt_seed ^ 0x4E415445)
		(
			data
			. pets
			. append(
				{
					"instanceId": cap_count,
					"petId": pet_id,
					"level": 1,
					"exp": 0,
					"realmBreaks": 0,
					"aptitudeSeed": apt_seed,
					"natureSeed": nature_seed,
					"equips": {},
				}
			)
		)
		_ensure_pet_condition(cap_count)
		# 阵容未满自动上阵（FTUE：收服即入队，docs/16 序章）
		if not data.player.has("party"):
			data.player["party"] = []
		if data.player.party.size() < 3:
			data.player.party.append(cap_count)
	return _apply_quest(2, pet_id, 1)


## 灵宠详情：按存储种子重展开资质+性格（幂等）
func get_pet_detail(instance_id: int) -> Dictionary:
	for pet in data.pets:
		if int(pet.instanceId) != instance_id:
			continue
		var pet_row := {}
		for p in _tables.get("PetBase", []):
			if int(p.petId) == int(pet.petId):
				pet_row = p
				break
		if pet_row.is_empty():
			return {"error": "未知灵宠 %d" % int(pet.petId)}
		var stamina_milli := 100000
		var mood_milli := 100000
		for c in data.village.petConditions:
			if int(c.petInstanceId) == int(pet.instanceId):
				stamina_milli = int(c.staminaMilli)
				mood_milli = int(c.moodMilli)
				break
		return {
			"instanceId": int(pet.instanceId),
			"petId": int(pet.petId),
			"name": String(pet_row.name),
			"element": int(pet_row.element),
			"quality": int(pet_row.quality),
			"level": int(pet.level),
			"realmBreaks": int(pet.realmBreaks),
			"aptitudes": PetIndividuality.roll_aptitudes(pet_row, int(pet.aptitudeSeed)),
			"nature": PetIndividuality.roll_nature(pet_row, int(pet.natureSeed)),
			"breaksChain": PetIndividuality._as_array(pet_row.breaks),
			"captureNote": String(pet_row.captureNote),
			"stamina": stamina_milli / 1000,
			"mood": mood_milli / 1000,
			"inParty": data.player.get("party", []).has(int(pet.instanceId)),
			"levelCap": PetGrowth.level_cap(int(pet.realmBreaks), _g()),
			"feedCost": PetGrowth.feed_cost(int(pet.level), _g()),
			"error": "",
		}
	return {"error": "实例不存在 %d" % instance_id}


func on_party_changed(size: int) -> Array:
	return _apply_quest(6, 0, size)


# ---------- 阵伍与成长（docs/01 §144 修为驱动 / docs/04 §2-§4） ----------


func _g() -> Dictionary:
	return _tables.get("GlobalConst", {})


## 当前阵伍（instanceId 列表；旧档缺字段时空）
func party() -> Array:
	return data.player.get("party", [])


## 上阵/下阵切换；阵伍上限 3；返回 {ok, error, size}
func toggle_party(instance_id: int) -> Dictionary:
	var party_arr: Array = data.player.get("party", [])
	if party_arr.has(instance_id):
		party_arr.erase(instance_id)
		data.player.party = party_arr
		return {"ok": true, "error": "", "size": party_arr.size()}
	var owned := false
	for pet in data.pets:
		if int(pet.instanceId) == instance_id:
			owned = true
			break
	if not owned:
		return {"ok": false, "error": "未拥有该灵宠", "size": party_arr.size()}
	if party_arr.size() >= 3:
		return {"ok": false, "error": "阵伍已满（3）", "size": party_arr.size()}
	party_arr.append(instance_id)
	data.player.party = party_arr
	return {"ok": true, "error": "", "size": party_arr.size()}


## 修为喂养 +1 级（docs/01 §144：修为为唯一养成资源；数值临时口径见 GlobalConst）
func feed_pet(instance_id: int) -> Dictionary:
	for pet in data.pets:
		if int(pet.instanceId) != instance_id:
			continue
		var res: Dictionary = PetGrowth.feed(pet, int(data.player.cultivation), _g())
		if bool(res.ok):
			data.player.cultivation = int(data.player.cultivation) - int(res.cost)
			pet.level = int(res.level)
		return res
	return {"ok": false, "reason": "实例不存在 %d" % instance_id}


## 突破（docs/02 §3.3 门槛/消耗；docs/04 §4 突破链）
func breakthrough_pet(instance_id: int) -> Dictionary:
	for pet in data.pets:
		if int(pet.instanceId) != instance_id:
			continue
		var pet_row := {}
		for p in _tables.get("PetBase", []):
			if int(p.petId) == int(pet.petId):
				pet_row = p
				break
		var res: Dictionary = PetGrowth.breakthrough(
			pet, pet_row, int(data.player.cultivation), _g()
		)
		if bool(res.ok):
			data.player.cultivation = int(data.player.cultivation) - int(res.cost)
			pet.realmBreaks = int(res.realmBreaks)
		return res
	return {"ok": false, "reason": "实例不存在 %d" % instance_id}


## 穿戴：需已鉴定；同部位自动替换（旧件卸下）；返回 {ok, error}
func wear_equipment(equip_instance_id: String, pet_instance_id: int) -> Dictionary:
	var item: Dictionary = {}
	for it in data.equipment.items:
		if String(it.instanceId) == equip_instance_id:
			item = it
			break
	if item.is_empty():
		return {"ok": false, "error": "装备实例不存在"}
	if not bool(item.identified):
		return {"ok": false, "error": "未鉴定装备不可穿戴"}
	var view: Dictionary = EquipDropResolver.resolve_identification(item, _equip_config, _g())
	if String(view.error) != "":
		return {"ok": false, "error": String(view.error)}
	var slot := int(view.slot)
	var pet: Dictionary = {}
	for p0 in data.pets:
		if int(p0.instanceId) == pet_instance_id:
			pet = p0
			break
	if pet.is_empty():
		return {"ok": false, "error": "灵宠实例不存在"}
	# 从其他灵宠身上卸下同实例
	for p1 in data.pets:
		var eq1: Dictionary = p1.get("equips", {})
		for k in eq1.keys():
			if String(eq1[k]) == equip_instance_id:
				eq1.erase(k)
	if not pet.has("equips"):
		pet["equips"] = {}
	pet.equips[slot] = equip_instance_id
	return {"ok": true, "error": "", "slot": slot}


## 装备展示视图：鉴定信息 + 强化等级 + 穿戴者（UI 渲染用；未鉴定返回占位）
func equipment_view(equip_instance_id: String) -> Dictionary:
	for item in data.equipment.items:
		if String(item.instanceId) != equip_instance_id:
			continue
		var out: Dictionary = {
			"instanceId": equip_instance_id,
			"equipId": int(item.equipId),
			"identified": bool(item.identified),
			"enhanceLevel": int(item.get("enhanceLevel", 0)),
			"wornBy": 0,
			"error": "",
		}
		if not bool(item.identified):
			return out
		var view: Dictionary = EquipDropResolver.resolve_identification(item, _equip_config, _g())
		if String(view.error) != "":
			out.error = String(view.error)
			return out
		out.slot = int(view.slot)
		out.mainStat = String(view.mainStat)
		out.mainValue = roundi(float(view.mainValueMicro) / 1000000.0)
		out.quality = int(view.quality)
		out.affixCount = view.affixes.size()
		for p0 in data.pets:
			var eq: Dictionary = p0.get("equips", {})
			for k in eq.keys():
				if String(eq[k]) == equip_instance_id:
					out.wornBy = int(p0.instanceId)
		return out
	return {"error": "装备实例不存在"}


## 卸下
func takeoff_equipment(equip_instance_id: String) -> Dictionary:
	for p0 in data.pets:
		var eq: Dictionary = p0.get("equips", {})
		for k in eq.keys():
			if String(eq[k]) == equip_instance_id:
				eq.erase(k)
				return {"ok": true, "error": ""}
	return {"ok": false, "error": "未被穿戴"}


## 强化（docs/08 §7.1）：消耗 铁锭(item204)+灵晶；成功率按档；上限=锻造炉等级×3；
## 失败仅耗材料不掉级（失败惩罚 docs 未定，标注待策划）；roll 按装备种子确定性派生
func enhance_equipment(equip_instance_id: String) -> Dictionary:
	var item: Dictionary = {}
	for it in data.equipment.items:
		if String(it.instanceId) == equip_instance_id:
			item = it
			break
	if item.is_empty():
		return {"ok": false, "error": "装备实例不存在"}
	var level := int(item.get("enhanceLevel", 0))
	if level >= 15:
		return {"ok": false, "error": "已达强化上限 +15"}
	var forge_level := BuildingEffects.level_of(data.village.buildings, BuildingEffects.FORGE)
	var cap := EquipEnhance.max_enhance_level(forge_level)
	if level >= cap:
		return {"ok": false, "error": "锻造炉等级不足（上限 +%d）" % cap}
	var cost: Dictionary = EquipEnhance.enhance_cost(level)
	var ingot := int(cost.metalIngot)
	var crystal := int(cost.spiritCrystal)
	if int(data.wallet.spiritCrystal) < crystal:
		return {"ok": false, "error": "灵晶不足（需 %d）" % crystal}
	var have_ingot := 0
	for st in data.village.storage:
		if int(st.itemId) == 204:
			have_ingot = int(st.amount)
			break
	if have_ingot < ingot:
		return {"ok": false, "error": "铁锭不足（需 %d）" % ingot}
	# 扣材料（失败也耗材料；成功率档位 docs/08 §7.1）
	data.wallet.spiritCrystal = int(data.wallet.spiritCrystal) - crystal
	for st in data.village.storage:
		if int(st.itemId) == 204:
			st.amount = int(st.amount) - ingot
			break
	var roll := _draw_equip_stream()
	var success := roll < EquipEnhance.enhance_success_rate(level)
	if success:
		item.enhanceLevel = level + 1
	return {"ok": true, "error": "", "success": success, "level": int(item.enhanceLevel)}


## 从持久化掉落流（streamId=2，docs/15 §3.2 五流之一）抽 [0,1)：推进并回写 state/drawCount，
## 确保强化重试每次是新抽样且离线回放一致（BattleRng 状态推进 = +M mod 2^32）
func _draw_equip_stream() -> float:
	for st in data.rng.streams:
		if int(st.streamId) == 2:
			var rng := BattleRng.new(int(st.state))
			var v := rng.next()
			st.state = (int(st.state) + 0x6D2B79F5) & 0xFFFFFFFF
			st.drawCount = int(st.drawCount) + 1
			return v
	return 0.5  # 无流兜底（存档异常时不应到达）


## 图鉴幸运值（docs/08 §3）：掉落 roll 的 luckValue 输入
func codex_luck() -> int:
	return CodexSystem.luck_bonus(data.pets, _all_pet_ids())


func _all_pet_ids() -> Array:
	var ids: Array = []
	for row in _tables.get("PetBase", []):
		ids.append(int(row.petId))
	return ids


## 出战队伍：阵伍灵宠 → 真实资质+性格+等级+突破；空阵伍回退序章演示三兽（docs/16）
func build_battle_team() -> Array:
	var team: Array = []
	var cfg := _build_battle_cfg()
	for instance_id in data.player.get("party", []):
		for pet in data.pets:
			if int(pet.instanceId) != int(instance_id):
				continue
			var pet_row := {}
			for p in _tables.get("PetBase", []):
				if int(p.petId) == int(pet.petId):
					pet_row = p
					break
			if pet_row.is_empty():
				continue
			var apts: Dictionary = PetIndividuality.roll_aptitudes(pet_row, int(pet.aptitudeSeed))
			var nature := PetIndividuality.roll_nature(pet_row, int(pet.natureSeed))
			# 装备修正（docs/08）：平面加成走 statMods，比例修正并入 natureMods 偏移通道
			var emods: Dictionary = EquipStats.equipped_mods(
				pet, data.equipment.items, _equip_config, _tables.get("EquipSet", []), _g()
			)
			var mods: Dictionary = PetIndividuality.nature_modifiers(nature).duplicate()
			for stat_key in emods.ratio:
				mods[stat_key] = float(mods.get(stat_key, 0.0)) + float(emods.ratio[stat_key])
			team.append(
				BattleSetup.make_pet_input(
					cfg,
					int(pet.petId),
					int(pet.level),
					900,
					int(pet.realmBreaks),
					{"apts": apts, "natureMods": mods, "statMods": emods.flat}
				)
			)
			break
	if team.is_empty():
		for t in FTUE_TEAM_IDS:
			team.append(BattleSetup.make_pet_input(cfg, int(t[0]), int(t[1]), int(t[2]), int(t[3])))
	return team


func on_crop_harvested(crop_id: int) -> Array:
	return _apply_quest(5, crop_id, 1)


# ---------- 装备掉落与鉴定（docs/08 §12） ----------


## 关卡胜利结算：dropCount 件装备 → 持久化实例（剥除演出字段）→ 任务 goalType 3
func settle_stage_drop(stage: Dictionary, root_seed: int) -> Dictionary:
	settlement_seq += 1
	var request := {
		"rootSeed": root_seed,
		"settlementSeq": settlement_seq,
		"dropId": int(stage.dropId),
		"dropCount": int(stage.dropCount),
		"monsterLevel": 12,
		"luckValue": float(CodexSystem.luck_bonus(data.pets, _all_pet_ids())),
		"pityState":
		{
			"schemaVersion": 1,
			"counters": data.equipment.pityCounters.duplicate(),
		},
	}
	var g: Dictionary = _tables.get("GlobalConst", {})
	var res: Dictionary = EquipDropResolver.resolve_settlement(request, _equip_config, g)
	if String(res.error) != "":
		return res
	for item in res.items:
		(
			data
			. equipment
			. items
			. append(
				{
					"instanceId": String(item.instanceId),
					"equipId": int(item.equipId),
					"quality": int(item.quality),
					"level": int(item.level),
					"rollSeed": int(item.rollSeed),
					"identified": bool(item.identified),
					"enhanceLevel": 0,
				}
			)
		)
	data.equipment.pityCounters = res.pityAfter.counters.duplicate()
	data.equipment.appliedSettlementIds.append(settlement_seq)
	_apply_quest(3, 0, int(res.items.size()))
	return res


## 免费鉴定：按实例存储种子展开（幂等）→ 任务 goalType 4
func identify_equipment(instance_id: String) -> Dictionary:
	for item in data.equipment.items:
		if String(item.instanceId) == instance_id:
			var g: Dictionary = _tables.get("GlobalConst", {})
			var view: Dictionary = EquipDropResolver.resolve_identification(item, _equip_config, g)
			if not bool(item.identified):
				item.identified = true
				_apply_quest(4, 0, 1)
			return view
	return {"error": "实例不存在：%s" % instance_id}


# ---------- 村落与离线（docs/15 §2 / docs/26 §3） ----------


func plant_crop(slot_id: int, crop_id: int, now_utc: int) -> Dictionary:
	for f in data.village.fields:
		if int(f.slotId) == slot_id:
			return {"ok": false, "error": "田位已占用"}
	# 灵田田位上限（docs/05 §2 kind 1）
	if slot_id > BuildingEffects.field_slots(data.village.buildings, _building_rows()):
		return {"ok": false, "error": "田位不足——升级灵田"}
	data.village.fields.append({"slotId": slot_id, "cropId": crop_id, "startedAtUtcSec": now_utc})
	return {"ok": true, "error": ""}


## 建筑升级（docs/05 §2）：议事堂等级门 + 货币扣减 + 等级 upsert（业务决策收口在会话层）
func upgrade_building(building_id: int) -> Dictionary:
	var row := {}
	for r in _building_rows():
		if int(r.buildingId) == building_id:
			row = r
			break
	if row.is_empty():
		return {"ok": false, "error": "未知建筑 %d" % building_id}
	var level := BuildingEffects.level_of(data.village.buildings, building_id)
	if level >= BuildingEffects.upgrade_cap(data.village.buildings, building_id, _building_rows()):
		return {"ok": false, "error": "已达上限（议事堂约束）"}
	var cost := int(row.upgradeCostBase) + int(row.upgradeCostStep) * level
	var currency := String(row.upgradeCostKey)
	if int(data.wallet.get(currency, 0)) < cost:
		return {
			"ok": false,
			"error": "%s不足（需 %d）" % ["灵晶" if currency == "spiritCrystal" else "兽贝", cost]
		}
	data.wallet[currency] = int(data.wallet.get(currency, 0)) - cost
	var found := false
	for b in data.village.buildings:
		if int(b.buildingId) == building_id:
			b.level = int(b.level) + 1
			found = true
			break
	if not found:
		data.village.buildings.append(
			{"buildingId": building_id, "level": 1, "damagedUntilUtcSec": 0}
		)
	return {"ok": true, "error": "", "level": level + 1, "cost": cost}


## 矿场开采（docs/05 §6/§4）：矿位数 = 矿场建筑效果；pet_instance_ids 绑宠派遣（效率乘算）
func assign_mine(mine_id: int, now_utc: int, pet_instance_ids: Array = []) -> Dictionary:
	var mine_row := {}
	for m in _tables.get("Mine", []):
		if int(m.mineId) == mine_id:
			mine_row = m
			break
	if mine_row.is_empty():
		return {"ok": false, "error": "未知矿层 %d" % mine_id}
	var slots := BuildingEffects.mine_slots(data.village.buildings, _building_rows())
	if data.village.mineJobs.size() >= slots:
		return {"ok": false, "error": "矿位已满（%d）——升级矿场" % slots}
	var next_slot := 1
	for j in data.village.mineJobs:
		next_slot = maxi(next_slot, int(j.slotId) + 1)
	# 派遣绑宠（docs/05 §4）：体力 ≥20 才可派遣；绑宠作业产量按派遣效率乘算
	var g0: Dictionary = _g()
	var assigned: Array = []
	for pid in pet_instance_ids:
		var cond := _condition_of(int(pid))
		if PetDispatch.can_dispatch(cond, g0):
			assigned.append(int(pid))
	var eff := 1.0
	if not assigned.is_empty():
		var sum := 0.0
		for pid in assigned:
			sum += PetDispatch.dispatch_efficiency(_condition_of(int(pid)), 0.0, g0)
		eff = sum / float(assigned.size())
	(
		data
		. village
		. mineJobs
		. append(
			{
				"slotId": next_slot,
				"mineId": mine_id,
				"startedAtUtcSec": now_utc,
				"assignedPetInstanceIds": assigned,
				"efficiency": eff,
			}
		)
	)
	return {"ok": true, "error": "", "slotId": next_slot, "efficiency": eff}


func _condition_of(pet_instance_id: int) -> Dictionary:
	for c in data.village.petConditions:
		if int(c.petInstanceId) == pet_instance_id:
			return c
	return {"petInstanceId": pet_instance_id, "staminaMilli": 100000, "moodMilli": 100000}


## 锻造/药庐生产（docs/05 §7）：station 1=锻造炉 2=药庐；队列容量按对应建筑（kind 3）
func craft(recipe_id: int, now_utc: int) -> Dictionary:
	var row := {}
	for r in _tables.get("Recipe", []):
		if int(r.recipeId) == recipe_id:
			row = r
			break
	if row.is_empty():
		return {"ok": false, "error": "未知配方 %d" % recipe_id}
	var station_building := (
		BuildingEffects.FORGE if int(row.station) == 1 else BuildingEffects.ALCHEMY
	)
	var cap := BuildingEffects.queue_cap(data.village.buildings, station_building, _building_rows())
	var res: Dictionary = RecipeCraft.start_craft(
		data.village.recipeJobs, recipe_id, String(row.inputs), now_utc, data.village.storage, cap
	)
	if String(res.error) != "":
		return {"ok": false, "error": String(res.error)}
	data.village.recipeJobs = res.jobs
	data.village.storage = res.inventory
	return {"ok": true, "error": "", "queue": res.jobs.size(), "cap": cap}


## 体力/心情条目同步（捕捉时登记，docs/15 §3.2 petConditions）
func _ensure_pet_condition(instance_id: int) -> void:
	for c in data.village.petConditions:
		if int(c.petInstanceId) == instance_id:
			return
	data.village.petConditions.append(
		{"petInstanceId": instance_id, "staminaMilli": 100000, "moodMilli": 100000}
	)


## 离线/回归结算：作物→任务 g5 + 矿场→钱包/库存 + 兽潮→波次报告 + 配方产出 + 兽栏休息；返回汇总
func settle_offline(now_utc: int) -> Dictionary:
	var report := {}
	var cfg := _village_config_capped()
	# ① 作物（docs/15 §2；窗口受图腾柱离线上限约束）
	var cursor := int(data.settlement.cursors.villageProductionUtcSec)
	var res: Dictionary = VillageProduction.settle_crops(
		data.village.fields, cursor, now_utc, data.village.storage, cfg
	)
	data.village.fields = res.nextFields
	data.settlement.cursors.villageProductionUtcSec = now_utc
	data.village.storage = res.inventory
	for o in res.outputs:
		_apply_quest(5, int(o.itemId), 1)
	report["crops"] = res
	# ② 矿场（docs/26 §4.3 + docs/05 §4）：绑宠作业按当前体力/心情刷新效率快照（窗口内恒定）
	var mine_jobs: Array = []
	for j in data.village.mineJobs:
		var j2: Dictionary = j.duplicate()
		var ids: Array = j2.get("assignedPetInstanceIds", [])
		if not ids.is_empty():
			var g1: Dictionary = _g()
			var sum := 0.0
			for pid0 in ids:
				sum += PetDispatch.dispatch_efficiency(_condition_of(int(pid0)), 0.0, g1)
			j2["efficiency"] = sum / float(ids.size())
		mine_jobs.append(j2)
	var mine_res: Dictionary = MineProduction.settle_mines(
		mine_jobs, cursor, now_utc, data.wallet, data.village.storage, cfg
	)
	data.wallet = mine_res.wallet
	data.village.storage = mine_res.inventory
	report["mines"] = mine_res
	# ③ 兽潮错过补结算（docs/26 §4.5，docs/15 §1.5）
	if data.pets.size() > 0:
		var tide_cursor := int(data.settlement.cursors.beastTideUtcSec)
		var team: Array = _build_defense_team()
		var g: Dictionary = _tables.get("GlobalConst", {})
		var tide_res: Dictionary = BeastTide.settle_missed(
			tide_cursor,
			now_utc,
			28800,
			int(data.rng.rootSeed),
			team,
			_tables,
			_build_battle_cfg(),
			g
		)
		data.settlement.cursors.beastTideUtcSec = tide_res.nextCursor
		report["beastTide"] = tide_res
	# ④ 配方生产结算（docs/05 §7）：到时任务产出入库（仓库倍率生效）
	var craft_cursor := int(data.settlement.cursors.get("craftUtcSec", cursor))
	var craft_res: Dictionary = RecipeCraft.settle_crafts(
		data.village.recipeJobs,
		now_utc,
		data.village.storage,
		Callable(self, "_recipe_of"),
		_village_config.categoryOf,
		_village_config.storageRules,
		BuildingEffects.storage_cap_mult(data.village.buildings, _building_rows())
	)
	data.village.recipeJobs = craft_res.nextJobs
	data.village.storage = craft_res.inventory
	data.settlement.cursors["craftUtcSec"] = now_utc
	report["crafts"] = craft_res
	# ⑤ 派遣体力消耗（docs/05 §4）+ 兽栏休息（仅未派遣，docs/05 §2 kind 4）
	var barn_level := BuildingEffects.level_of(data.village.buildings, BuildingEffects.BARN)
	var window_hours := clampf(
		float(now_utc - cursor) / 3600.0, 0.0, float(_offline_cap_sec()) / 3600.0
	)
	var dispatched := {}
	for j in data.village.mineJobs:
		for pid1 in j.get("assignedPetInstanceIds", []):
			dispatched[int(pid1)] = true
	var rested := 0
	for i in range(data.village.petConditions.size()):
		var cond: Dictionary = data.village.petConditions[i]
		if dispatched.has(int(cond.petInstanceId)):
			cond = PetDispatch.settle_dispatch(cond, window_hours, _village_config.g)
		else:
			cond = PetDispatch.settle_rest(cond, window_hours, barn_level, _village_config.g)
			rested += 1
		data.village.petConditions[i] = cond
	report["rest"] = {"pets": rested, "hours": window_hours}
	data.meta.updatedAtUtcSec = now_utc
	data.meta.lastObservedUtcSec = now_utc
	_store_report_summary(now_utc, report)
	return report


## 结算报告摘要入 pendingReports（docs/15 §3.5：游标幂等防重复发奖；此处存展示副本，留最近 5 份）
func _store_report_summary(now_utc: int, report: Dictionary) -> void:
	var pr: Dictionary = data.settlement.get("pendingReports", {})
	pr["%d" % now_utc] = {
		"at": now_utc,
		"cropOutputs": report.get("crops", {}).get("outputs", []).size(),
		"mineOutputs": report.get("mines", {}).get("outputs", []).size(),
		"spiritGained": _wallet_delta(report, "spiritCrystal"),
		"tideWaves": report.get("beastTide", {}).get("settledCount", 0),
		"craftOutputs": report.get("crafts", {}).get("outputs", []).size(),
		"restedPets": report.get("rest", {}).get("pets", 0),
	}
	while pr.size() > 5:
		var oldest := ""
		for k in pr.keys():
			if oldest == "" or String(k) < oldest:
				oldest = String(k)
		pr.erase(oldest)
	data.settlement.pendingReports = pr


func _wallet_delta(report: Dictionary, _key: String) -> int:
	# 钱包增量从矿场输出推（itemId=-1 为灵晶）
	var total := 0
	for o in report.get("mines", {}).get("outputs", []):
		if int(o.itemId) == -1:
			total += int(o.amount)
	return total


## 人话摘要行（开屏结算报告用）
func offline_summary_lines(report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var crops: Array = report.get("crops", {}).get("outputs", [])
	if not crops.is_empty():
		var total := 0
		for o in crops:
			total += int(o.amount)
		lines.append("灵田收获 %d 笔（共 %d 份）" % [crops.size(), total])
	var mines: Array = report.get("mines", {}).get("outputs", [])
	if not mines.is_empty():
		var spirit := 0
		var items_n := 0
		for o in mines:
			if int(o.itemId) == -1:
				spirit += int(o.amount)
			else:
				items_n += 1
		lines.append("矿场产出 %d 笔（灵晶 +%d）" % [items_n + (1 if spirit > 0 else 0), spirit])
	var tide: Dictionary = report.get("beastTide", {})
	if int(tide.get("settledCount", 0)) > 0:
		var wins := 0
		for w in tide.get("waves", []):
			if String(w.outcome) == "victory":
				wins += 1
		lines.append("兽潮防守 %d 波（胜 %d）" % [int(tide.settledCount), wins])
	var crafts: Array = report.get("crafts", {}).get("outputs", [])
	if not crafts.is_empty():
		lines.append("锻造/炼丹完成 %d 件" % crafts.size())
	var rest: Dictionary = report.get("rest", {})
	if int(rest.get("pets", 0)) > 0:
		lines.append("兽栏休整 %d 只灵宠（%.1f 小时）" % [int(rest.pets), float(rest.hours)])
	if lines.is_empty():
		lines.append("离线期间暂无产出")
	return lines


func _recipe_of(recipe_id: int) -> Dictionary:
	for r in _tables.get("Recipe", []):
		if int(r.recipeId) == recipe_id:
			return r
	return {}


## 兽潮守村队 = 出战队（阵伍真实资质/性格/突破；docs/05 §9）
func _build_defense_team() -> Array:
	return build_battle_team()


func _build_battle_cfg() -> Dictionary:
	if _battle_cfg.is_empty():
		_battle_cfg = BattleSetup.build_cfg(_tables)
	return _battle_cfg
