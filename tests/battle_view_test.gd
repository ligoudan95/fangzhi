## doc: 13 §3 / §13 D11-12
## 演出层验收：BattlePlayback 节奏/倍速/跳过/finished 恰好一次；
## battle.tscn 冒烟——注入结果回放，日志与结果横幅渲染正确（headless 无渲染，验证节点逻辑）。
extends GdUnitTestSuite

const BattleScene := preload("res://scenes/battle.tscn")


func _make_playback() -> BattlePlayback:
	return BattlePlayback.new(["R1 甲攻击", "  → 乙受到 10 点伤害", "== 战斗结束：胜利"])


func test_playback_paces_lines_in_order() -> void:
	var p := _make_playback()
	var got: Array[String] = []
	while not p.is_done():
		got.append_array(p.tick(0.31))
	assert_array(got).is_equal(["R1 甲攻击", "  → 乙受到 10 点伤害", "== 战斗结束：胜利"])


func test_playback_speed_2x_doubles_rate() -> void:
	var p := _make_playback()
	p.speed = 2.0
	var first: Array = p.tick(0.31)
	# 2x 间隔 0.15s：0.31s 应吐出 2 行（1x 只吐 1 行）
	assert_int(first.size()).is_equal(2)


func test_playback_skip_flushes_all_and_finishes() -> void:
	var p := _make_playback()
	var rest := p.skip()
	assert_int(rest.size()).is_equal(3)
	assert_bool(p.is_done()).is_true()
	assert_int(p.remaining()).is_equal(0)
	assert_array(p.tick(1.0)).is_empty()


func test_playback_finished_emits_exactly_once() -> void:
	var p := _make_playback()
	# GDScript lambda 按值捕获整型——用字典引用累计
	var counter := {"n": 0}
	p.finished.connect(func() -> void: counter["n"] += 1)
	p.skip()
	p.skip()
	for i in range(5):
		p.tick(1.0)
	assert_int(counter["n"]).is_equal(1)


## 场景冒烟：注入战斗结果 → 跳过 → 日志全量渲染 + 结果横幅含回合数
func test_scene_smoke_renders_result() -> void:
	var scene: Control = auto_free(BattleScene.instantiate())
	add_child(scene)
	var result := {
		"outcome": "victory",
		"rounds": 9,
		"log": ["R1 演出冒烟", "  → 演出冒烟受伤 1 点", "== 战斗结束：胜利"],
		"capturedPetId": -1,
	}
	scene.start_result(result, "冒烟关卡")
	scene._on_skip_pressed()
	var log_text: RichTextLabel = scene.get_node("Margin/VBox/LogScroll/LogText")
	assert_str(log_text.text).contains("R1 演出冒烟")
	assert_str(log_text.text).contains("战斗结束")
	var result_label: Label = scene.get_node("Margin/VBox/Result")
	assert_str(result_label.text).contains("胜利")
	assert_str(result_label.text).contains("9")


## 场景冒烟：空结果立即结束不崩（边界）
func test_scene_smoke_empty_log() -> void:
	var scene: Control = auto_free(BattleScene.instantiate())
	add_child(scene)
	scene.start_result({"outcome": "timeout", "rounds": 30, "log": []}, "空场景")
	var result_label: Label = scene.get_node("Margin/VBox/Result")
	assert_str(result_label.text).contains("超时判负")
