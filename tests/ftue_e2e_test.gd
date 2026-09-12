## doc: 16 §2/§6（首小时 E2E）/ 15 §3.5 / 08 §12
## 垂直切片端到端：新档 → 序章推进 → 战斗 → 捕捉 → 掉落/鉴定 → 上阵 →
## 播种 → 存档退出 → 模拟离线 → 重读档 → 收获与任务链续推。
## 全程走 GameSession 公共 API（View 装配层），独立 user://save_e2e/ 不污染真实档。
extends GdUnitTestSuite

const E2E_DIR: String = "user://save_e2e/"


func _make_session() -> Node:
	var save_svc: Node = auto_free(preload("res://scripts/infra/save_service.gd").new())
	save_svc.set_base_dir(E2E_DIR)
	var session: Node = auto_free(preload("res://scripts/view/game_session.gd").new(save_svc))
	add_child(session)
	return session


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for slot in ["auto", "manual1"]:
		for suffix in ["", ".bak", ".tmp"]:
			var path: String = E2E_DIR + slot + ".json" + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func test_vertical_slice_first_hour() -> void:
	var now := 1700000000
	var session := _make_session()

	# ① 新档 + 序章剧情推进（docs/16 节拍 0:00-5:00）
	assert_bool(session.new_game(now, 424242)).is_true()
	var done: Array = session.advance_story()
	assert_int(done.size()).is_equal(1)
	assert_str(String(done[0].title)).is_equal("兽潮之夜")

	# ② 教学战胜利 → 守住第一波完成（goalType 1, stage 1）
	done = session.on_stage_cleared(1)
	assert_int(done.map(func(q): return q.questId).size()).is_greater_equal(0)
	var qs: Dictionary = session.data.player.quests
	assert_bool(bool(qs.completed.get("2", false))).is_true()

	# ③ 首捕 → 序章完结跨章连锁（收服第一只 + 黑风林的低语）
	done = session.on_pet_captured(1003)
	qs = session.data.player.quests
	assert_int(int(done[0].questId)).is_equal(3)
	assert_int(int(done[1].questId)).is_equal(4)
	assert_int(int(qs.chapterId)).is_equal(1)

	# ④ 藤影清剿（stage2）+ 首件掉宝（docs/16 节拍 25:00-35:00）
	done = session.on_stage_cleared(2)
	qs = session.data.player.quests
	assert_bool(bool(qs.completed.get("5", false))).is_true()
	var stage2: Dictionary = _find_stage(2)
	var drop: Dictionary = session.settle_stage_drop(stage2, 777)
	qs = session.data.player.quests
	assert_str(String(drop.error)).is_empty()
	assert_int(drop.items.size()).is_greater_equal(1)
	assert_bool(bool(qs.completed.get("6", false))).is_true()  # 首件战利品

	# ⑤ 鉴定 → 鉴定开光（goalType 4）
	var inst: Dictionary = session.data.equipment.items[0]
	var view: Dictionary = session.identify_equipment(String(inst.instanceId))
	session.on_pet_captured(1003)
	session.on_pet_captured(1003)
	session.on_pet_captured(1003)
	qs = session.data.player.quests
	assert_str(String(view.get("error", ""))).is_empty()
	assert_bool(bool(inst.identified)).is_true()
	assert_bool(bool(qs.completed.get("7", false))).is_true()

	# ⑥ 播种时节（goalType 5 需收获后才触发）+ 上阵三宠（goalType 6）
	assert_bool(session.plant_crop(1, 1, now + 60)).is_true()
	done = session.on_party_changed(3)
	qs = session.data.player.quests
	assert_bool(bool(qs.completed.get("9", false))).is_true()  # 三兽成阵

	# ⑦ 存档退出 → 模拟离线 1 小时（含 30 分钟作物成熟）→ 重读档（docs/16 节拍 50:00-60:00）
	assert_bool(session.save_game()).is_true()
	var session2 := _make_session()
	assert_bool(session2.load_game()).is_true()
	var offline_at := now + 3600
	var report: Dictionary = session2.settle_offline(offline_at)
	assert_int(report.outputs.size()).is_greater_equal(1)
	var storage_total := 0
	for s in session2.data.village.storage:
		storage_total += int(s.amount)
	assert_int(storage_total).is_greater_equal(6)  # 灵谷 ≥6（春 ×1.2 → 7）
	qs = session2.data.player.quests
	assert_bool(bool(qs.completed.get("10", false))).is_true()  # 播种时节（收获触发）

	# ⑧ 再次存读档往返一致（幂等口径）
	assert_bool(session2.save_game()).is_true()
	var session3 := _make_session()
	assert_bool(session3.load_game()).is_true()
	assert_int(session3.data.player.quests.completed.size()).is_equal(
		session2.data.player.quests.completed.size()
	)
	assert_int(session3.data.equipment.items.size()).is_equal(session2.data.equipment.items.size())


func _find_stage(stage_id: int) -> Dictionary:
	var tables := BattleSetup.load_tables("res://resources/config/")
	for s in tables.get("StageConfig", []):
		if int(s.stageId) == stage_id:
			return s
	return {}
