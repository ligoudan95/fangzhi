## doc: 23 §1
## 设置浮层（View）：五总线音量即时生效（AudioServer + linear_to_db）、总静音、
## 减少动态、粒子档位、字号档位。关闭即保存；由战斗工具栏唤起，模态覆盖不挡战斗结算。
## text_scale 本阶段仅持久化（UI 布局级缩放随设置页正式化接入，docs/14 记录）。
extends CanvasLayer

signal closed

const BUS_IDS: Dictionary = {
	"bgm": "BGM",
	"amb": "Amb",
	"sfx_battle": "SFX_Battle",
	"sfx_work": "SFX_Work",
	"ui": "UI",
}

var _settings: Dictionary = {}
var _sliders: Dictionary = {}
var _mute_check: CheckButton
var _motion_check: CheckButton
var _particle_option: OptionButton
var _text_option: OptionButton


func _ready() -> void:
	_settings = SettingsStore.load_settings()
	_build_ui()
	apply_audio()


## 即时应用音频总线（docs/11 §7 五通道）
func apply_audio() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), bool(_settings.master_mute))
	for bus_key in BUS_IDS:
		var index := AudioServer.get_bus_index(String(BUS_IDS[bus_key]))
		if index < 0:
			continue
		var linear := clampf(float(_settings.volumes[bus_key]), 0.0, 1.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(linear))


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 900)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var audio_header := _header("音频")
	box.add_child(audio_header)
	for bus_key in SettingsStore.BUS_KEYS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(BUS_IDS[bus_key])
		label.custom_minimum_size = Vector2(160, 0)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(_settings.volumes[bus_key])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_volume_changed.bind(bus_key))
		row.add_child(label)
		row.add_child(slider)
		box.add_child(row)
		_sliders[bus_key] = slider

	_mute_check = _check("总静音")
	_mute_check.button_pressed = bool(_settings.master_mute)
	_mute_check.toggled.connect(_on_mute_toggled)
	box.add_child(_mute_check)

	box.add_child(_header("显示"))
	_motion_check = _check("减少动态效果（关闭震屏/闪烁）")
	_motion_check.button_pressed = bool(_settings.reduce_motion)
	_motion_check.toggled.connect(_on_motion_toggled)
	box.add_child(_motion_check)

	var particle_row := HBoxContainer.new()
	var particle_label := Label.new()
	particle_label.text = "粒子质量"
	particle_label.custom_minimum_size = Vector2(200, 0)
	_particle_option = OptionButton.new()
	for mode in ["自动", "高", "低"]:
		_particle_option.add_item(mode)
	_particle_option.selected = SettingsStore.PARTICLE_MODES.find(
		String(_settings.particle_quality)
	)
	_particle_option.item_selected.connect(_on_particle_selected)
	particle_row.add_child(particle_label)
	particle_row.add_child(_particle_option)
	box.add_child(particle_row)

	box.add_child(_header("文本"))
	var text_row := HBoxContainer.new()
	var text_label := Label.new()
	text_label.text = "字号缩放"
	text_label.custom_minimum_size = Vector2(200, 0)
	_text_option = OptionButton.new()
	for scale_label in ["100%", "115%", "130%"]:
		_text_option.add_item(scale_label)
	_text_option.selected = SettingsStore.TEXT_SCALES.find(float(_settings.text_scale))
	_text_option.item_selected.connect(_on_text_selected)
	text_row.add_child(text_label)
	text_row.add_child(_text_option)
	box.add_child(text_row)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 72)
	close.pressed.connect(_on_close_pressed)
	box.add_child(close)


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 30)
	return label


func _check(text: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	return check


func _persist() -> void:
	SettingsStore.save_settings(_settings)


func _on_volume_changed(value: float, bus_key: String) -> void:
	_settings.volumes[bus_key] = value
	apply_audio()
	_persist()


func _on_mute_toggled(pressed: bool) -> void:
	_settings.master_mute = pressed
	apply_audio()
	_persist()


func _on_motion_toggled(pressed: bool) -> void:
	_settings.reduce_motion = pressed
	_persist()


func _on_particle_selected(index: int) -> void:
	_settings.particle_quality = SettingsStore.PARTICLE_MODES[index]
	_persist()


func _on_text_selected(index: int) -> void:
	_settings.text_scale = SettingsStore.TEXT_SCALES[index]
	_persist()


func _on_close_pressed() -> void:
	_persist()
	closed.emit()
	queue_free()
