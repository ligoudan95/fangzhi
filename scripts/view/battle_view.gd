## doc: 10 §8 / 13 §3 D11-12 + M6 第一阶段
## 战斗演出视图——消费结构化事件队列（docs/10 §8.1）：2×3 站位、Tween 动势、
## 池化伤害数字、捕捉横幅；文本日志保留为战报（对拍与复盘口径）。
## View 零业务逻辑：只消费 Battle 产物；无事件时回退纯文本回放（兼容旧测试注入）。
extends Control

## 战斗回放完成（正常/跳过均恰好一次，随结果横幅首显发出）；result 为 BattleResult 字典
signal battle_finished(result: Dictionary)

## 演示阵容：灰岩獒(坦) + 桃夭狐(疗) + 朱羽雉(输出)，与对拍场景一致
const TEAM: Array = [[1001, 12, 900, 1], [1002, 12, 900, 1], [1005, 12, 950, 1]]
## 五行属性色（docs/10 §2.1）：占位贴图着色，正式立绘到位后替换
const ELEMENT_COLORS: Dictionary = {
	1: Color("#E8B33C"),
	2: Color("#6FBF4F"),
	3: Color("#4F86E8"),
	4: Color("#E8543C"),
	5: Color("#C79A4B"),
	6: Color("#7A4FD4"),
	7: Color("#F5E7B8")
}

## 窗口宽高比（竖屏 9:16）：任意拖拽后吸附回该比例，内容等比满幅
const WINDOW_ASPECT := 9.0 / 16.0

var _seed: int = 0
var _playback: BattlePlayback
var _events_playback: BattleEventPlayback
var _last_result: Dictionary = {}
var _actor_by_uid: Dictionary = {}
var _number_pool: Array[Label] = []
var _snapping := false
var _number_seq := 0
var _battlefield_origin := Vector2.ZERO
var _battlefield_origin_valid := false
var _uid_pet := {}

@onready var title_label: Label = $Margin/VBox/Title
@onready var round_label: Label = $Margin/VBox/Round
@onready var stage_option: OptionButton = $Margin/VBox/Toolbar/StageOption
@onready var log_text: RichTextLabel = $Margin/VBox/LogScroll/LogText
@onready var result_label: Label = $Margin/VBox/Result
@onready var speed_button: Button = $Margin/VBox/Toolbar/SpeedButton
@onready var enemy_row: HBoxContainer = $Margin/VBox/Battlefield/EnemyRow
@onready var ally_row: HBoxContainer = $Margin/VBox/Battlefield/AllyRow
@onready var number_layer: Control = $NumberLayer


func _ready() -> void:
	_setup_window()
	_play_bgm("res://assets/audio/bgm_battle.wav")
	_populate_stages()
	if _config() != null:
		_new_battle()


## BGM/SFX 挂钩（docs/11 §7）：Audio Autoload 缺失（headless/测试）时静默跳过
func _play_bgm(path: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_bgm(path)


func _sfx(path: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_sfx(path)


## 桌面窗口自适应：任意拖拽后吸附回 9:16（宽:高），内容等比满幅；
## 初始位置按可用工作区（扣任务栏）精确居中。headless 无窗口语义，跳过。
func _setup_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	win.min_size = Vector2i(324, 576)
	win.size = Vector2i(594, 1056)
	win.size_changed.connect(_snap_window_aspect)
	_center_window()


func _center_window() -> void:
	await get_tree().process_frame
	var win := get_window()
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var pos := usable.position + (usable.size - win.size) / 2
	win.position = Vector2i(pos)
	_clamp_window_into_workarea(win, usable)


## 滞回吸附：偏差 >2px 才纠正，防 resize 事件自激；尺寸与位置均钳入工作区（防底边出屏裁内容）
func _snap_window_aspect() -> void:
	if _snapping:
		return
	_snapping = true
	var win := get_window()
	if win.mode == Window.MODE_MAXIMIZED or win.mode == Window.MODE_FULLSCREEN:
		_snapping = false
		return
	var size := win.size
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var target_h := int(round(float(size.x) / WINDOW_ASPECT))
	target_h = mini(target_h, usable.size.y - 16)
	if absi(target_h - size.y) > 2:
		var target_w := int(round(float(target_h) * WINDOW_ASPECT))
		win.size = Vector2i(maxi(324, target_w), maxi(576, target_h))
	_clamp_window_into_workarea(win, usable)
	_snapping = false


func _clamp_window_into_workarea(win: Window, usable: Rect2i) -> void:
	var pos := win.position
	pos.y = mini(pos.y, usable.position.y + usable.size.y - win.size.y)
	pos.y = maxi(pos.y, usable.position.y)
	pos.x = mini(pos.x, usable.position.x + usable.size.x - win.size.x)
	pos.x = maxi(pos.x, usable.position.x)
	win.position = pos


func _process(delta: float) -> void:
	if _playback == null:
		return
	if not _playback.is_done():
		for line in _playback.tick(delta):
			_append_line(line)
	if _events_playback != null and not _events_playback.is_done():
		for e in _events_playback.tick(delta):
			_apply_event(e)


## 直接注入结果回放（测试/外部驱动用）；事件存在时驱动站位演出，日志仅作战报
func start_result(result: Dictionary, stage_title: String = "") -> void:
	_last_result = result
	title_label.text = stage_title
	log_text.text = ""
	result_label.text = ""
	round_label.text = ""
	_actor_by_uid = {}
	for child in enemy_row.get_children():
		child.queue_free()
	for child in ally_row.get_children():
		child.queue_free()
	_playback = BattlePlayback.new(result.get("log", []))
	_playback.finished.connect(_show_result)
	var events: Array = result.get("events", [])
	if not events.is_empty():
		_events_playback = BattleEventPlayback.new(events)
		_events_playback.finished.connect(_show_result)
	else:
		_events_playback = null
		if result.get("log", []).is_empty():
			_show_result()


func _append_line(line: String) -> void:
	log_text.text += line + "\n"


## ---------- 事件应用（docs/10 §8.2 通用反馈） ----------


func _apply_event(e: Dictionary) -> void:
	match String(e.get("t", "")):
		"start":
			_on_start(e)
		"round":
			round_label.text = "第 %d 回合" % int(e.r)
		"cast":
			_on_cast(e)
		"hit":
			_on_hit(e)
		"dodge":
			_spawn_number(int(e.u), "闪避", Color("#D8D8D8"), 22)
		"heal":
			_on_heal(e)
		"shield":
			_spawn_number(int(e.u), "+盾 %d" % int(e.a), Color("#4F9DE8"), 24)
			_flash(int(e.u), Color("#4F9DE8"))
		"buff":
			_spawn_number(int(e.u), "【%s】" % String(e.b), Color("#A64FE8"), 20)
		"death":
			_on_death(int(e.u))
		"sub":
			_on_sub(e)
		"cap":
			_on_capture(e)
		"end":
			round_label.text = ""


func _on_start(e: Dictionary) -> void:
	for unit in e.get("units", []):
		_uid_pet[int(unit.u)] = _pet_id_by_name(String(unit.n))
		_make_actor_slot(int(unit.u), int(unit.s), String(unit.n), int(unit.hp), int(unit.el))


## 名字→petId：从 Config 的 PetBase 表查（无表时回退 0 → 色块占位）
func _pet_id_by_name(pet_name: String) -> int:
	var cfg_node := _config()
	if cfg_node == null:
		return 0
	for row in cfg_node.get_rows("PetBase"):
		if String(row.name) == pet_name:
			return int(row.petId)
	return 0


func _on_cast(e: Dictionary) -> void:
	var slot = _actor_by_uid.get(int(e.u))
	if slot == null:
		return
	var panel: PanelContainer = slot
	var dir := -36.0 if int(panel.get_meta("side")) == 0 else 36.0
	var base_y := panel.position.y
	var tween := panel.create_tween()
	(
		tween
		. tween_property(panel, "position:y", base_y + dir, 0.12)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(panel, "position:y", base_y, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN
	)
	var skill_label: Label = panel.get_meta("skill_label")
	skill_label.text = "【%s】" % String(e.get("s", ""))
	skill_label.modulate.a = 1.0
	var fade := panel.create_tween()
	fade.tween_interval(0.5)
	fade.tween_property(skill_label, "modulate:a", 0.0, 0.3)


func _on_hit(e: Dictionary) -> void:
	var uid := int(e.u)
	var dmg := int(e.d)
	var crit := int(e.c) == 1
	_update_hp(uid, int(e.hp))
	if dmg > 0:
		_spawn_number(
			uid, str(dmg), Color("#F0923C") if crit else Color("#E9E2D0"), 40 if crit else 30
		)
		_sfx("res://assets/audio/sfx_crit.wav" if crit else "res://assets/audio/sfx_hit.wav")
		_flash(uid, Color(2.2, 2.2, 2.2))
		_shake_battlefield(6.0 if crit else 3.0)
	else:
		_spawn_number(uid, "盾", Color("#4F9DE8"), 22)


func _on_heal(e: Dictionary) -> void:
	_update_hp(int(e.u), int(e.hp))
	_spawn_number(int(e.u), "+%d" % int(e.a), Color("#52C462"), 30)
	_sfx("res://assets/audio/sfx_heal.wav")
	_flash(int(e.u), Color("#52C462"))


func _on_death(uid: int) -> void:
	_sfx("res://assets/audio/sfx_death.wav")
	var slot = _actor_by_uid.get(uid)
	if slot == null:
		return
	var panel: PanelContainer = slot
	var tween := panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate", Color(0.35, 0.35, 0.35, 0.45), 0.45)
	tween.tween_property(panel, "position:y", panel.position.y + 20.0, 0.45)
	slot.set_meta("alive", false)


func _on_sub(e: Dictionary) -> void:
	_uid_pet[int(e.u)] = _pet_id_by_name(String(e.n))
	_make_actor_slot(int(e.u), int(e.s), String(e.n), 1, 0)
	_spawn_number(int(e.u), "替补入场", Color("#F5E7B8"), 24)


func _on_capture(e: Dictionary) -> void:
	_sfx(
		(
			"res://assets/audio/sfx_capture_ok.wav"
			if int(e.ok) == 1
			else "res://assets/audio/sfx_capture_fail.wav"
		)
	)
	var ok := int(e.ok) == 1
	var banner := Label.new()
	banner.text = "收服！%d%%" % int(e.rt) if ok else "挣脱了…%d%%" % int(e.rt)
	banner.add_theme_font_size_override("font_size", 44 if ok else 30)
	banner.add_theme_color_override("font_color", Color("#F0923C") if ok else Color("#D8D8D8"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(290, 640)
	number_layer.add_child(banner)
	var tween := banner.create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(banner, "scale", Vector2(1.15, 1.15), 0.3)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(banner, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tween.chain().tween_callback(banner.queue_free)


## ---------- 站位与表现 ----------


func _make_actor_slot(uid: int, side: int, unit_name: String, hp: int, element: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 240)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# docs/10 §4.2：程序化占位贴图（tools/dev/gen_placeholder_art.gd）→ 缺失回退元素色块
	var portrait: Control = _make_portrait(uid, element)
	var name_label := Label.new()
	name_label.text = ("[敌]" if side == 1 else "") + unit_name
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color("#E9E2D0"))
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = hp
	hp_bar.value = hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(180, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#52C462")
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.13, 0.1)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_bar.add_theme_stylebox_override("background", bg)
	var skill_label := Label.new()
	skill_label.add_theme_font_size_override("font_size", 26)
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_label.modulate.a = 0.0
	box.add_child(portrait)
	box.add_child(name_label)
	box.add_child(hp_bar)
	box.add_child(skill_label)
	panel.add_child(box)
	panel.set_meta("hp_bar", hp_bar)
	panel.set_meta("skill_label", skill_label)
	panel.set_meta("alive", true)
	panel.set_meta("side", side)
	var row: HBoxContainer = enemy_row if side == 1 else ally_row
	row.add_child(panel)
	_actor_by_uid[uid] = panel


## 立绘占位（docs/10 §4.2）：按 uid 查表加载贴图，缺失时回退元素色块
func _make_portrait(uid: int, element: int) -> Control:
	var pet_id := _pet_id_by_uid(uid)
	var path := "res://art/pets/pet_%d/battle_idle.png" % pet_id
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.custom_minimum_size = Vector2(160, 190)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var fallback := ColorRect.new()
	fallback.custom_minimum_size = Vector2(160, 190)
	fallback.color = ELEMENT_COLORS.get(element, Color("#6E6A66"))
	return fallback


## uid→petId：start 事件快照按序建立 _uid_pet 映射；替补也在此登记
func _pet_id_by_uid(uid: int) -> int:
	if _uid_pet.has(uid):
		return int(_uid_pet[uid])
	return 0


func _update_hp(uid: int, hp: int) -> void:
	var slot = _actor_by_uid.get(uid)
	if slot == null:
		return
	var hp_bar: ProgressBar = slot.get_meta("hp_bar")
	hp_bar.value = maxf(0.0, float(hp))


func _flash(uid: int, color: Color) -> void:
	if _reduce_motion():
		return
	var slot = _actor_by_uid.get(uid)
	if slot == null:
		return
	# 杀已有 flash tween 防闪烁叠加（快速连击时旧 tween 未完会被覆盖）
	if slot.has_meta("flash_tween") and slot.get_meta("flash_tween") is Tween:
		var old: Tween = slot.get_meta("flash_tween")
		if old.is_valid():
			old.kill()
	slot.set_meta("flash_tween", slot.create_tween())
	var tween: Tween = slot.get_meta("flash_tween")
	slot.modulate = color
	tween.tween_property(slot, "modulate", Color.WHITE, 0.18)


## 震屏只动 Battlefield，不动 HUD 与安全区（docs/10 §11）；减少动态时跳过（docs/23 §2）
## 防累计漂移：记录真实原点，连震时杀旧 tween 再从原点开始


func _shake_battlefield(px: float) -> void:
	if _reduce_motion():
		return
	var battlefield: Control = $Margin/VBox/Battlefield
	if not _battlefield_origin_valid:
		_battlefield_origin = battlefield.position
		_battlefield_origin_valid = true
	var tween := battlefield.create_tween()
	tween.finished.connect(func() -> void: _battlefield_origin_valid = false)
	for i in 3:
		var offset := Vector2(px if i % 2 == 0 else -px, 0)
		tween.tween_property(battlefield, "position", _battlefield_origin + offset, 0.04)
	tween.tween_property(battlefield, "position", _battlefield_origin, 0.05)


## 池化伤害数字（docs/10 §11）：复用 Label，上浮淡出后回收
func _spawn_number(uid: int, text: String, color: Color, font_size: int) -> void:
	var slot = _actor_by_uid.get(uid)
	var label: Label = _acquire_number()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.modulate.a = 1.0
	# 确定性散开：按 uid 哈希偏移防多数字完全重叠（不引入随机流，docs/15 §3.5）
	_number_seq += 1
	var jitter := Vector2(
		float((uid * 13 + _number_seq * 7) % 54) - 27.0, float((uid * 7 + _number_seq * 11) % 14)
	)
	if slot != null:
		label.position = slot.global_position + Vector2(slot.size.x * 0.5 - 80.0, -36.0) + jitter
	else:
		label.position = Vector2(480, 800) + jitter
	var tween := label.create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(label, "position:y", label.position.y - 64.0, 0.55)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.15)
	tween.chain().tween_callback(func() -> void: _release_number(label))


func _acquire_number() -> Label:
	for label in _number_pool:
		if not label.is_visible_in_tree() and label.modulate.a <= 0.01:
			label.visible = true
			return label
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(160, 40)
	number_layer.add_child(label)
	_number_pool.append(label)
	return label


func _release_number(label: Label) -> void:
	label.modulate.a = 0.0
	label.visible = false


## ---------- 组局与控制（沿用 D11-12 口径） ----------


## 配置→战斗：Config 表组局，选中场次首波敌人
func _replay() -> void:
	var cfg_node := _config()
	if cfg_node == null:
		return
	var tables: Dictionary = cfg_node.get_all()
	var cfg := BattleSetup.build_cfg(tables)
	var team: Array = []
	for t in TEAM:
		team.append(BattleSetup.make_pet_input(cfg, int(t[0]), int(t[1]), int(t[2]), int(t[3])))
	var stages: Array = cfg_node.get_rows("StageConfig")
	if stages.is_empty():
		return
	var idx := maxi(0, stage_option.selected)
	var stage: Dictionary = stages[mini(idx, stages.size() - 1)]
	var group := int(stage.waves[0])
	var battle := Battle.new(cfg, team, BattleSetup.group_inputs(tables, cfg, group), _seed)
	var title := "关卡%d %s" % [int(stage.stageId), String(stage.name)]
	start_result(battle.run(), title)


func _new_battle() -> void:
	_seed = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	_replay()


func _show_result() -> void:
	if _playback == null:
		return
	if result_label.text.is_empty():
		result_label.text = "%s · %d 回合" % [_outcome_cn(), int(_last_result.get("rounds", 0))]
		battle_finished.emit(_last_result)


func _outcome_cn() -> String:
	match String(_last_result.get("outcome", "")):
		"victory":
			return "胜利"
		"defeat":
			return "失败"
		"captured":
			return "捕捉成功"
		_:
			return "超时判负"


## Autoload 在 headless 脚本模式下不存在（测试环境）；运行时经 /root/Config
func _config() -> Node:
	return get_node_or_null("/root/Config")


func _populate_stages() -> void:
	var cfg_node := _config()
	if cfg_node == null:
		stage_option.add_item("（测试模式）")
		return
	for row in cfg_node.get_rows("StageConfig"):
		stage_option.add_item("%d·%s" % [int(row.stageId), String(row.name)])


func _on_speed_pressed() -> void:
	if _playback == null:
		return
	_playback.speed = 2.0 if _playback.speed == 1.0 else 1.0
	if _events_playback != null:
		_events_playback.speed = _playback.speed
	speed_button.text = "2x" if _playback.speed == 2.0 else "1x"


func _on_skip_pressed() -> void:
	if _playback == null:
		return
	for line in _playback.skip():
		_append_line(line)
	if _events_playback != null:
		for e in _events_playback.skip():
			_apply_event(e)


func _on_replay_pressed() -> void:
	_replay()


func _on_new_battle_pressed() -> void:
	_new_battle()


## 设置浮层（docs/23）：模态覆盖，关闭即释放；View 层不落业务状态
func _on_settings_pressed() -> void:
	var overlay: CanvasLayer = preload("res://scripts/view/settings_view.gd").new()
	add_child(overlay)


## 减少动态（docs/23 §2）：关闭震屏与快速闪烁
func _reduce_motion() -> bool:
	return bool(SettingsStore.load_settings().reduce_motion)
