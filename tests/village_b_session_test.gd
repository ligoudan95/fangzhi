## doc: 05 §2/§6/§7 / 26 §4（Phase B 会话粘合）
## GameSession 建筑升级门/矿位/配方生产/田位上限 + 村落面板渲染冒烟
extends GdUnitTestSuite

const VILLAGE_SCENE: PackedScene = preload("res://scenes/village.tscn")
const SAVE_DIR: String = "user://save_village_b_test/"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.dir_exists("save_village_b_test"):
		for f in dir.get_files_at("save_village_b_test"):
			dir.remove("save_village_b_test/%s" % f)
		dir.remove("save_village_b_test")


func _make_session() -> Node:
	var save_svc: Node = load("res://scripts/infra/save_service.gd").new()
	save_svc.set_base_dir(SAVE_DIR)
	var session: Node = load("res://scripts/view/game_session.gd").new(save_svc)
	add_child(session)
	session.new_game(1000000, 424242)
	return session


func test_upgrade_hall_gate_and_cost() -> void:
	var session := _make_session()
	# 议事堂 lv0 → 其他建筑升级被门挡
	var res: Dictionary = session.upgrade_building(4)
	assert_bool(bool(res.ok)).is_false()
	assert_str(String(res.error)).contains("议事堂")
	# 灵晶不足
	res = session.upgrade_building(1)
	assert_bool(bool(res.ok)).is_false()
	assert_str(String(res.error)).contains("不足")
	# 给钱升级议事堂 → 灵田可升
	session.data.wallet.spiritCrystal = 10000
	res = session.upgrade_building(1)
	assert_bool(bool(res.ok)).is_true()
	assert_int(int(res.level)).is_equal(1)
	res = session.upgrade_building(4)
	assert_bool(bool(res.ok)).is_true()
	# 升级后田位 = 3 + 1 = 4
	var plant_over: Dictionary = session.plant_crop(5, 1, 2000000)
	assert_bool(bool(plant_over.ok)).is_false()
	var plant_ok: Dictionary = session.plant_crop(4, 1, 2000000)
	assert_bool(bool(plant_ok.ok)).is_true()


func test_assign_mine_slot_cap() -> void:
	var session := _make_session()
	session.data.village.buildings.append({"buildingId": 5, "level": 0, "damagedUntilUtcSec": 0})
	var r1: Dictionary = session.assign_mine(1, 1000000)
	assert_bool(bool(r1.ok)).is_true()
	assert_int(int(r1.slotId)).is_equal(1)
	# 矿场 lv0 → 1 矿位，第二个拒绝
	var r2: Dictionary = session.assign_mine(2, 1000001)
	assert_bool(bool(r2.ok)).is_false()
	assert_str(String(r2.error)).contains("矿位已满")
	# 升矿场（先升议事堂解锁）→ 可再开
	session.data.village.buildings.append({"buildingId": 1, "level": 2, "damagedUntilUtcSec": 0})
	session.data.wallet.spiritCrystal = 10000
	session.upgrade_building(5)
	var r3: Dictionary = session.assign_mine(2, 1000002)
	assert_bool(bool(r3.ok)).is_true()


func test_craft_flow_and_offline_settle() -> void:
	var session := _make_session()
	# 锻造炉 lv0 → 队列 1；配方 4 需 201×2+206×2
	session.data.village.buildings.append({"buildingId": 7, "level": 0, "damagedUntilUtcSec": 0})
	var no_mat: Dictionary = session.craft(4, 1000000)
	assert_bool(bool(no_mat.ok)).is_false()
	assert_str(String(no_mat.error)).is_equal("材料不足")
	# 给料入队（队列 1 满）：201×5−2=3，206×3−2=1
	session.data.village.storage = [{"itemId": 201, "amount": 5}, {"itemId": 206, "amount": 3}]
	var ok: Dictionary = session.craft(4, 1000000)
	assert_bool(bool(ok.ok)).is_true()
	assert_int(session.data.village.recipeJobs.size()).is_equal(1)
	assert_int(session.data.village.storage.size()).is_equal(2)
	assert_int(int(session.data.village.storage[1].amount)).is_equal(1)
	var queued: Dictionary = session.craft(4, 1000001)
	assert_bool(bool(queued.ok)).is_false()
	# 30 分钟后离线结算 → 产物 206 入库、队列清空（余 1 + 产物 1 = 2）
	session.settle_offline(1000000 + 31 * 60)
	assert_int(session.data.village.recipeJobs.size()).is_equal(0)
	var found_206 := 0
	for s in session.data.village.storage:
		if int(s.itemId) == 206:
			found_206 = int(s.amount)
	assert_int(found_206).is_equal(2)


func test_village_panel_renders_recipes() -> void:
	var session := _make_session()
	session.data.village.buildings.append({"buildingId": 7, "level": 0, "damagedUntilUtcSec": 0})
	var village: Control = auto_free(VILLAGE_SCENE.instantiate())
	add_child(village)
	village.setup(session)
	village._on_building_pressed(7)
	assert_bool(village.info_panel.visible).is_true()
	assert_str(String(village.info_title.text)).is_equal("锻造炉")
	# 锻造炉 station=1 配方至少 1 行（开始按钮）
	var action_rows := 0
	for child in village.action_list.get_children():
		if child is HBoxContainer:
			action_rows += 1
	assert_int(action_rows).is_greater_equal(1)
	# 矿场面板：矿位行
	village._on_building_pressed(5)
	assert_str(String(village.info_title.text)).is_equal("矿场")
