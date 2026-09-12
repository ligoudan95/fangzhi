## doc: 10 §8（开发用界面帧自证工具）
## 以运行窗口模式加载战斗场景 → 快进整场 → 从根视口取最终渲染帧存 PNG。
## 用于视觉验收：捕获像素 == 用户所见（含 stretch/缩放链路），绕开 OS 截图伪影。
## 运行：godot --path . -s res://tools/dev/ui_frame_capture.gd
extends SceneTree

var _frames := 0
var _scene: Control


func _initialize() -> void:
	_scene = preload("res://scenes/battle.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		_scene._on_skip_pressed()
	elif _frames == 10:
		_capture()
	return false


func _capture() -> void:
	var log_text: RichTextLabel = _scene.get_node("Margin/VBox/LogScroll/LogText")
	var log_scroll: ScrollContainer = _scene.get_node("Margin/VBox/LogScroll")
	print(
		"UI-DEBUG: log_chars=", log_text.text.length(),
		" log_rect=", log_text.global_position, log_text.size,
		" scroll_rect=", log_scroll.global_position, log_scroll.size,
		" vbox_rect=", _scene.get_node("Margin/VBox").size
	)
	var img := root.get_texture().get_image()
	var out := "res://.godot/ui_frame_%dx%d.png" % [img.get_width(), img.get_height()]
	img.save_png(out)
	print("UI-FRAME-SAVED: ", out, " window=", root.size, " scale=", root.content_scale_factor)
	quit(0)
