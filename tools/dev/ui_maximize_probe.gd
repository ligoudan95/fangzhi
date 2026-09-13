## doc: 10 §12（最大化回归探针，开发用）
## 复现用户场景：游戏中最大化窗口 → WindowFit 应转为工作区内最大 9:16 窗口居中。
## 运行：godot --path . -s res://tools/dev/ui_maximize_probe.gd
extends SceneTree

var _frames := 0
var _scene: Control


func _initialize() -> void:
	_scene = preload("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		_scene._on_new_game_pressed()
		print("BEFORE-MAX: mode=", root.mode, " size=", root.size)
		root.mode = Window.MODE_MAXIMIZED
	elif _frames == 30:
		print("T+20F: mode=", root.mode, " size=", root.size)
	elif _frames == 60:
		print("T+50F: mode=", root.mode, " size=", root.size)
	elif _frames == 90:
		var ratio := float(root.size.x) / float(root.size.y)
		print("FINAL: mode=", root.mode, " size=", root.size, " ratio=%.4f" % ratio)
		var img := root.get_texture().get_image()
		img.save_png("res://.godot/ui_maximize_check.png")
		print("CAPTURED ", img.get_size())
		quit(0)
	return false
