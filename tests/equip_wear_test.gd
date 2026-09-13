## doc: 08 §7（穿戴/强化）/ §3（图鉴幸运）
## 装备穿戴与强化会话集成：鉴定→穿戴→出战队属性管线；强化流/上限/材料；幸运接掉落
extends GdUnitTestSuite

const SAVE_DIR: String = "user://save_equip_wear_test/"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.dir_exists("save_equip_wear_test"):
		for f in dir.get_files_at("save_equip_wear_test"):
			dir.remove("save_equip_wear_test/%s" % f)
		dir.remove("save_equip_wear_test")


func _make_session() -> Node:
	var save_svc: Node = load("res://scripts/infra/save_service.gd").new()
	save_svc.set_base_dir(SAVE_DIR)
	var session: Node = load("res://scripts/view/game_session.gd").new(save_svc)
	add_child(session)
	session.new_game(1000000, 424242)
	return session


func _drop_some(session: Node, count: int) -> Array:
	var stage: Dictionary = {}
	for s0 in BattleSetup.load_tables("res://resources/config/").get("StageConfig", []):
		if int(s0.stageId) == 2:
			stage = s0
			break
	stage.dropCount = count
	var res: Dictionary = session.settle_stage_drop(stage, 777)
	assert_str(String(res.error)).is_empty()
	return session.data.equipment.items


func test_wear_requires_identified_and_replaces_slot() -> void:
	var session := _make_session()
	session.on_pet_captured(1003)
	var items: Array = _drop_some(session, 2)
	# 未鉴定不可穿
	var unid: Dictionary = session.wear_equipment(String(items[0].instanceId), 1)
	assert_bool(bool(unid.ok)).is_false()
	assert_str(String(unid.error)).contains("未鉴定")
	# 鉴定后可穿；slot 写入 pet.equips
	session.identify_equipment(String(items[0].instanceId))
	var worn: Dictionary = session.wear_equipment(String(items[0].instanceId), 1)
	assert_bool(bool(worn.ok)).is_true()
	var pet: Dictionary = session.data.pets[0]
	assert_int(pet.equips.size()).is_equal(1)
	# 出战队带装备平面加成（借兽补位至 3，玩家宠在首位）
	var team: Array = session.build_battle_team()
	assert_int(team.size()).is_equal(3)
	assert_bool(team[0].get("statMods", {}).size() > 0).is_true()


func test_wear_moves_item_between_pets() -> void:
	var session := _make_session()
	session.on_pet_captured(1003)
	session.on_pet_captured(1001)
	var items: Array = _drop_some(session, 1)
	var iid := String(items[0].instanceId)
	session.identify_equipment(iid)
	session.wear_equipment(iid, 1)
	assert_int(int(session.equipment_view(iid).wornBy)).is_equal(1)
	# 同件穿给 2 号 → 1 号自动卸下
	session.wear_equipment(iid, 2)
	assert_int(int(session.equipment_view(iid).wornBy)).is_equal(2)
	assert_int(session.data.pets[0].equips.size()).is_equal(0)
	session.takeoff_equipment(iid)
	assert_int(int(session.equipment_view(iid).wornBy)).is_equal(0)


func test_enhance_cap_materials_and_stream() -> void:
	var session := _make_session()
	var items: Array = _drop_some(session, 1)
	var iid := String(items[0].instanceId)
	session.identify_equipment(iid)
	# 锻造炉 lv0 → 上限 +0 → 拒绝
	var no_forge: Dictionary = session.enhance_equipment(iid)
	assert_bool(bool(no_forge.ok)).is_false()
	assert_str(String(no_forge.error)).contains("锻造炉")
	# 建锻造炉 lv3（上限 +9）+ 灵晶充足但缺铁锭
	session.data.village.buildings.append({"buildingId": 7, "level": 3, "damagedUntilUtcSec": 0})
	session.data.wallet.spiritCrystal = 100000
	var no_ingot: Dictionary = session.enhance_equipment(iid)
	assert_bool(bool(no_ingot.ok)).is_false()
	assert_str(String(no_ingot.error)).contains("铁锭")
	session.data.village.storage.append({"itemId": 204, "amount": 50})
	# +1~+3 必成功；重试经掉落流推进（每次新抽样）
	var enhanced := 0
	for i in 3:
		var r: Dictionary = session.enhance_equipment(iid)
		assert_bool(bool(r.ok)).is_true()
		assert_bool(bool(r.success)).is_true()  # +0→+1/+1→+2/+2→+3 全 100%
		enhanced = int(r.level)
	assert_int(enhanced).is_equal(3)
	# 材料扣了 3 次（铁锭 1+2+3=6；灵晶 500+650+845）
	assert_int(int(session.data.village.storage[0].amount)).is_equal(44)
	assert_int(int(session.data.wallet.spiritCrystal)).is_equal(100000 - 500 - 650 - 845)
	# 掉落流 drawCount 推进
	var draws := 0
	for st in session.data.rng.streams:
		if int(st.streamId) == 2:
			draws = int(st.drawCount)
	assert_int(draws).is_equal(3)


func test_codex_luck_feeds_drop() -> void:
	var session := _make_session()
	# 0 收集 → 幸运 0
	assert_int(session.codex_luck()).is_equal(0)
	# 收集 1/12 种 → 完成度 8.3% → floor(0.083/0.05)=1 → +10
	session.on_pet_captured(1003)
	assert_int(session.codex_luck()).is_equal(10)
