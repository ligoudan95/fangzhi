## doc: 16 §2/§6（FTUE 主场景冒烟）/ 19 W2
## main.tscn 全流程冒烟：新档→剧情→教学战（注入胜利）→捕捉战→装备鉴定→
## 灵田播种→离线快进→保存→续档。走 main_view 公共处理器（真实 UI 信号路径）。
extends GdUnitTestSuite

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const E2E_DIR: String = "user://save_main_test/"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for slot in ["auto"]:
		for suffix in ["", ".bak", ".tmp"]:
			var path: String = E2E_DIR + slot + ".json" + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _make_main() -> Node:
	var scene: Control = auto_free(MAIN_SCENE.instantiate())
	add_child(scene)
	var save_svc: Node = scene.session._save
	save_svc.set_base_dir(E2E_DIR)
	return scene


func test_main_full_ftue_flow() -> void:
	var main: Node = _make_main()
	main._on_new_game_pressed()
	# 序章剧情已被 new_game 自动推进 → 激活"守住第一波"
	var quests: Array = main._tables.get("MainQuest", [])
	var qs: Dictionary = main.session.data.player.quests
	assert_str(String(main.quest_title.text)).is_equal("守住第一波")

	# 教学战：注入胜利结果（headless 不跑演出，直接喂事实回主流程回调）
	var stage1: Dictionary = main._find_stage(1)
	main._on_battle_finished(
		{"outcome": "victory", "rounds": 4, "log": [], "events": []}, stage1, false
	)
	qs = main.session.data.player.quests
	assert_bool(bool(qs.completed.get("2", false))).is_true()

	# 捕捉战：captured → 序章完结跨章
	main._on_battle_finished(
		{"outcome": "captured", "rounds": 3, "log": [], "events": [], "capturedPetId": 1003},
		stage1,
		true
	)
	qs = main.session.data.player.quests
	assert_int(int(qs.chapterId)).is_equal(1)

	# 出战按钮进入战斗覆盖层（真实战斗装配路径）
	main._on_battle_pressed()
	assert_bool(main.battle_overlay.visible).is_true()
	assert_int(main.battle_overlay.get_child_count()).is_greater_equal(1)

	# 藤影清剿（stage2）→ 首件掉宝链激活
	main._on_battle_finished(
		{"outcome": "victory", "rounds": 5, "log": [], "events": []}, main._find_stage(2), false
	)
	# 装备面板：注入掉落 → 鉴定
	main.session.settle_stage_drop(main._find_stage(2), 777)
	main._on_equip_pressed()
	assert_bool(main.equip_panel.visible).is_true()
	var inst: Dictionary = main.session.data.equipment.items[0]
	main._on_identify_pressed(String(inst.instanceId))
	assert_bool(bool(inst.identified)).is_true()

	# 灵田：播种 → 快进 1 小时 → 收获入任务
	main._on_farm_pressed()
	main._on_farm_plant_pressed()
	assert_int(main.session.data.village.fields.size()).is_equal(1)
	main._on_farm_skip_pressed()
	qs = main.session.data.player.quests
	assert_bool(bool(qs.completed.get("6", false))).is_true()  # 首件战利品之后链上的收获节点

	# 保存 → 续档往返
	main._on_save_pressed()
	for child in main.battle_overlay.get_children():
		main.battle_overlay.remove_child(child)
		child.free()
	var main2: Node = _make_main()
	main2._on_continue_pressed()
	assert_str(String(main2.quest_title.text)).is_equal(String(main.quest_title.text))
	assert_int(main2.session.data.equipment.items.size()).is_equal(
		main.session.data.equipment.items.size()
	)
