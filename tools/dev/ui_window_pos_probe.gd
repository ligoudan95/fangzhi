## doc: 10 §12（窗口定位坐标空间探针，开发用）
## 打印 position/size/工作区/缩放，判断逻辑像素与物理像素是否混算导致居中偏移。
## 运行：godot --path . -s res://tools/dev/ui_window_pos_probe.gd
extends SceneTree

var _frames := 0
var _scene: Control


func _initialize() -> void:
	_scene = preload("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames in [15, 45]:
		var win := root
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		var scale_f := DisplayServer.screen_get_scale(win.current_screen)
		var srect: Rect2i = DisplayServer.screen_get_usable_rect(win.current_screen)
		print(
			"PROBE f=%d pos=" % _frames,
			win.position,
			" size=",
			win.size,
			" usable=",
			usable,
			" usable2=",
			srect,
			" scale=%.3f" % scale_f,
			" | win_center=",
			win.position + win.size / 2,
			" usable_center=",
			usable.position + usable.size / 2
		)
	elif _frames == 46:
		quit(0)
	return false
