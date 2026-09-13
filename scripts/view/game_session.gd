## doc: 15 §3.5 / 16 §2 / 08 §12
## 垂直切片会话（View 层装配器）：读设备 UTC → 调 Config/Save/Logic；
## 写档成功才替换内存状态（docs/15 §3.5 单向流）。串联：
## 新档/读档 → 序章推进 → 战斗结算→任务 → 装备掉落→鉴定→任务 → 捕捉→任务
## → 播种/离线结算→收获→任务 → 存档往返。零业务规则：只做编排与事实搬运。
class_name GameSession
extends Node

const SAVE_SCRIPT: GDScript = preload("res://scripts/infra/save_service.gd")

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
				}
			)
		)
		_ensure_pet_condition(cap_count)
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
			"error": "",
		}
	return {"error": "实例不存在 %d" % instance_id}


func on_party_changed(size: int) -> Array:
	return _apply_quest(6, 0, size)


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
		"luckValue": 0.0,
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


## 矿场开采（docs/05 §6）：同时矿层数 = 矿场建筑效果（kind 1）
func assign_mine(mine_id: int, now_utc: int) -> Dictionary:
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
	data.village.mineJobs.append(
		{
			"slotId": next_slot,
			"mineId": mine_id,
			"startedAtUtcSec": now_utc,
			"assignedPetInstanceIds": []
		}
	)
	return {"ok": true, "error": "", "slotId": next_slot}


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
	# ② 矿场（docs/26 §4.3）
	var mine_res: Dictionary = MineProduction.settle_mines(
		data.village.mineJobs, cursor, now_utc, data.wallet, data.village.storage, cfg
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
	# ⑤ 兽栏休息（docs/05 §2 kind 4）：窗口小时内按兽栏等级恢复体力/心情
	var barn_level := BuildingEffects.level_of(data.village.buildings, BuildingEffects.BARN)
	var rest_hours := clampf(
		float(now_utc - cursor) / 3600.0, 0.0, float(_offline_cap_sec()) / 3600.0
	)
	for i in range(data.village.petConditions.size()):
		data.village.petConditions[i] = PetDispatch.settle_rest(
			data.village.petConditions[i], rest_hours, barn_level, _village_config.g
		)
	report["rest"] = {"pets": data.village.petConditions.size(), "hours": rest_hours}
	data.meta.updatedAtUtcSec = now_utc
	data.meta.lastObservedUtcSec = now_utc
	return report


func _recipe_of(recipe_id: int) -> Dictionary:
	for r in _tables.get("Recipe", []):
		if int(r.recipeId) == recipe_id:
			return r
	return {}


func _build_defense_team() -> Array:
	var team: Array = []
	var cfg := _build_battle_cfg()
	for pet in data.pets:
		team.append(BattleSetup.make_pet_input(cfg, int(pet.petId), int(pet.level), 900, 0))
	return team


func _build_battle_cfg() -> Dictionary:
	if _battle_cfg.is_empty():
		_battle_cfg = BattleSetup.build_cfg(_tables)
	return _battle_cfg
