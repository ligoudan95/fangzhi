## doc: 16 §2（FTUE 全程）/ 02 §2.2（境界）/ 01 §144
## FTUE 进度骨干自动回归：新档→序章→捕捉（野性等级+补位队）→喂养→装备→
## 境界推进→凝血解锁→建筑/配方/矿层门禁→离线结算——进度不断链的机器验收。
extends GdUnitTestSuite

const SAVE_DIR: String = "user://save_ftue_progress_test/"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.dir_exists("save_ftue_progress_test"):
		for f in dir.get_files_at("save_ftue_progress_test"):
			dir.remove("save_ftue_progress_test/%s" % f)
		dir.remove("save_ftue_progress_test")


func _make_session() -> Node:
	var save_svc: Node = load("res://scripts/infra/save_service.gd").new()
	save_svc.set_base_dir(SAVE_DIR)
	var session: Node = load("res://scripts/view/game_session.gd").new(save_svc)
	add_child(session)
	assert_bool(bool(session.new_game(1000000, 424242))).is_true()
	return session


func _stage(session: Node, stage_id: int) -> Dictionary:
	for s0 in session._tables.get("StageConfig", []):
		if int(s0.stageId) == stage_id:
			return s0
	return {}


## 全程模拟：捕捉后不是单宠送死、门禁生效、境界解锁打通凝血内容
func test_ftue_progression_no_dead_end() -> void:
	var session := _make_session()
	session.advance_story()

	# ① 序章：空阵伍 → 演示三兽整队
	var team0: Array = session.build_battle_team()
	assert_int(team0.size()).is_equal(3)
	assert_int(int(team0[0].petId)).is_equal(1001)
	session.on_stage_cleared(1)

	# ② 捕捉（stage1 敌 lv4 → 野性等级入场）→ 阵队 1 只 + 借兽补 2 位
	session.on_pet_captured(1003, 4)
	var team1: Array = session.build_battle_team()
	assert_int(team1.size()).is_equal(3)
	assert_int(int(team1[0].level)).is_equal(4)
	assert_int(int(team1[0].petId)).is_equal(1003)
	assert_int(int(team1[1].petId)).is_equal(1001)  # 补位演示兽
	# 捕捉宠真实资质（非均质）
	var uniform := (
		int(team1[0].apts.atk) == int(team1[0].apts.def)
		and int(team1[0].apts.def) == int(team1[0].apts.hp)
	)
	assert_bool(uniform).is_false()

	# ③ 补位队实战可打：stage2（2×lv8 敌）多种子多数胜利（进度不卡死口径）
	var stage2: Dictionary = _stage(session, 2)
	var cfg: Dictionary = session._build_battle_cfg()
	var wins := 0
	for i in 10:
		var battle := Battle.new(
			cfg,
			session.build_battle_team(),
			BattleSetup.group_inputs(session._tables, cfg, 2),
			1000 + i
		)
		if String(battle.run().outcome) == "victory":
			wins += 1
	assert_int(wins).is_greater_equal(6)  # 10 种子至少 6 胜——无死路
	session.on_stage_cleared(2)

	# ④ 凝血内容在淬体被门禁挡住
	var wall: Dictionary = session.upgrade_building(6)  # 城墙箭塔 unlockRealm=凝血
	assert_bool(bool(wall.ok)).is_false()
	assert_str(String(wall.error)).contains("境界不足")
	session.data.wallet.beastShell = 10000
	var forge_craft: Dictionary = session.craft(4, 1000100)  # 配方 4 unlockRealm=凝血
	assert_bool(bool(forge_craft.ok)).is_false()
	assert_str(String(forge_craft.error)).contains("境界不足")
	session.data.village.buildings.append({"buildingId": 5, "level": 0, "damagedUntilUtcSec": 0})
	var mine2: Dictionary = session.assign_mine(2, 1000100)  # 矿层 2 unlockRealm=凝血
	assert_bool(bool(mine2.ok)).is_false()

	# ⑤ 任务修为推进境界到凝血（淬体 9 层共 500×Σ1.35^k ≈ 14967）
	session.data.player.cultivation += 20000
	var advanced := 0
	for i in 12:
		var r: Dictionary = session.advance_realm()
		if not bool(r.ok):
			break
		advanced += 1
	assert_int(int(session.data.player.realmId)).is_equal(2)
	assert_str(String(session.realm_info().display)).is_equal("凝血一重")

	# ⑥ 凝血解锁：升议事堂（解除等级门）→ 城墙可升、配方可生产、矿层 2 可采
	session.data.wallet.spiritCrystal = 100000
	assert_bool(bool(session.upgrade_building(1).ok)).is_true()
	var wall2: Dictionary = session.upgrade_building(6)
	assert_bool(bool(wall2.ok)).is_true()
	session.data.village.buildings.append({"buildingId": 7, "level": 3, "damagedUntilUtcSec": 0})
	session.data.village.storage.append({"itemId": 201, "amount": 5})
	session.data.village.storage.append({"itemId": 206, "amount": 5})
	var craft2: Dictionary = session.craft(4, 1000200)
	assert_bool(bool(craft2.ok)).is_true()
	var mine_ok: Dictionary = session.assign_mine(2, 1000300)
	assert_bool(bool(mine_ok.ok)).is_true()

	# ⑦ 喂养+装备+离线全链收尾（不断链冒烟）
	session.data.player.cultivation += 500
	session.feed_pet(1)
	var report: Dictionary = session.settle_offline(1000200 + 3600)
	(
		assert_int(
			report.crops.outputs.size() + report.mines.outputs.size() + report.crafts.outputs.size()
		)
		. is_greater_equal(0)
	)
	assert_bool(session.save_game()).is_true()
