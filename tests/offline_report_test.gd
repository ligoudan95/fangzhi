## doc: 15 §1.5/§2（离线结算与回归展示）/ §3.5（pendingReports）
## 离线结算报告：摘要入库（留 5 份）、人话行、开屏面板冒烟
extends GdUnitTestSuite

const SAVE_DIR: String = "user://save_offline_report_test/"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.dir_exists("save_offline_report_test"):
		for f in dir.get_files_at("save_offline_report_test"):
			dir.remove("save_offline_report_test/%s" % f)
		dir.remove("save_offline_report_test")


func _make_session() -> Node:
	var save_svc: Node = load("res://scripts/infra/save_service.gd").new()
	save_svc.set_base_dir(SAVE_DIR)
	var session: Node = load("res://scripts/view/game_session.gd").new(save_svc)
	add_child(session)
	session.new_game(1000000, 424242)
	return session


func test_report_summary_stored_and_capped() -> void:
	var session := _make_session()
	session.plant_crop(1, 1, 1000000)
	var report: Dictionary = session.settle_offline(1000000 + 3600)
	# 作物 30 分钟成熟 → 1 笔产出；报告摘要入库
	var pr: Dictionary = session.data.settlement.pendingReports
	assert_int(pr.size()).is_equal(1)
	assert_int(int(pr["1003600"].cropOutputs)).is_equal(1)
	# 人话行非空且含灵田
	var lines: Array[String] = session.offline_summary_lines(report)
	assert_bool(lines.size() > 0).is_true()
	assert_str(String(lines[0])).contains("灵田")
	# 连续结算 6 次 → 只留最近 5 份
	for i in 5:
		session.settle_offline(1007200 + i * 3600)
	assert_int(session.data.settlement.pendingReports.size()).is_equal(5)


func test_report_panel_smoke() -> void:
	var session := _make_session()
	var scene: Control = auto_free(preload("res://scenes/main.tscn").instantiate())
	add_child(scene)
	scene._on_new_game_pressed()
	var lines: Array[String] = ["灵田收获 1 笔（共 7 份）", "兽栏休整 1 只灵宠（1.0 小时）"]
	scene._show_offline_report(3600, lines)
	assert_bool(scene.offline_report_panel.visible).is_true()
	assert_str(String(scene.offline_report_text.text)).contains("离开 1.0 小时")
	assert_str(String(scene.offline_report_text.text)).contains("灵田收获")
	# 领取关闭
	scene._on_offline_claim_pressed()
	assert_bool(scene.offline_report_panel.visible).is_false()
