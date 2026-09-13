## doc: 10 §8（开发用界面帧自证工具——主场景全流程）
## 以运行窗口模式加载 main.tscn → 新档→灵宠→装备→村落→灵田→保存，逐步截帧存 PNG。
## 步骤 03/05 故意不先关旧面板再开新面板，验证浮层互斥修复。
## 用于视觉验收：捕获像素 == 用户所见（含 stretch/缩放链路），绕开 OS 截图伪影。
## 运行：godot --path . -s res://tools/dev/ui_flow_capture.gd
extends SceneTree

const SAVE_DIR: String = "user://save_ui_flow/"

var _frames := 0
var _scene: Control


func _initialize() -> void:
	_scene = preload("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# _ready 已跑（首帧前触发），此时隔离存档目录，避免污染真实存档
		_scene.session._save.set_base_dir(SAVE_DIR)
	elif _frames == 4:
		_scene._on_new_game_pressed()
	elif _frames == 8:
		_capture("01_home")
	elif _frames == 12:
		_scene._on_pet_pressed()
	elif _frames == 16:
		_capture("02_pet_panel")
	elif _frames == 20:
		# 互斥验证：灵宠面板开着直接按装备，应只见装备面板
		_scene._on_equip_pressed()
	elif _frames == 24:
		_capture("03_equip_exclusive")
	elif _frames == 28:
		# 互斥验证：装备面板开着直接进村落，应只见村落
		_scene._on_village_pressed()
	elif _frames == 32:
		_capture("04_village")
	elif _frames == 36:
		# 互斥验证：村落开着直接按灵田，应只见灵田
		_scene._on_farm_pressed()
	elif _frames == 40:
		_capture("05_farm")
	elif _frames == 44:
		_scene._on_farm_plant_pressed()
	elif _frames == 48:
		_scene._on_farm_skip_pressed()
	elif _frames == 52:
		_scene._on_farm_close_pressed()
		_scene._on_save_pressed()
	elif _frames == 56:
		_capture("06_final")
		quit(0)
	return false


func _capture(tag: String) -> void:
	var img := root.get_texture().get_image()
	var out := "res://.godot/ui_test_%s.png" % tag
	img.save_png(out)
	print("UI-FRAME-SAVED: ", out, " size=", img.get_size())
