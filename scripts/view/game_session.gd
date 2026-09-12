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
	return _apply_quest(2, pet_id, 1)


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


func plant_crop(slot_id: int, crop_id: int, now_utc: int) -> bool:
	for f in data.village.fields:
		if int(f.slotId) == slot_id:
			return false
	data.village.fields.append({"slotId": slot_id, "cropId": crop_id, "startedAtUtcSec": now_utc})
	return true


## 离线/回归结算：作物→任务 g5 + 矿场→钱包/库存 + 兽潮→波次报告；返回汇总
func settle_offline(now_utc: int) -> Dictionary:
	var report := {}
	# ① 作物（docs/15 §2）
	var cursor := int(data.settlement.cursors.villageProductionUtcSec)
	var res: Dictionary = VillageProduction.settle_crops(
		data.village.fields, cursor, now_utc, data.village.storage, _village_config
	)
	data.village.fields = res.nextFields
	data.settlement.cursors.villageProductionUtcSec = now_utc
	data.village.storage = res.inventory
	for o in res.outputs:
		_apply_quest(5, int(o.itemId), 1)
	report["crops"] = res
	# ② 矿场（docs/26 §4.3）
	var mine_res: Dictionary = MineProduction.settle_mines(
		data.village.mineJobs, cursor, now_utc, data.wallet, data.village.storage, _village_config
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
	data.meta.updatedAtUtcSec = now_utc
	data.meta.lastObservedUtcSec = now_utc
	return report


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
