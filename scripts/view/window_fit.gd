## doc: 10 §12（竖屏 9:16 自适应窗口，任意尺寸界面清晰）
## 全局窗口适配器：任意拖拽后吸附回 9:16（宽:高）；最大化/全屏等过渡稳定后
## 转为工作区内最大的 9:16 窗口居中（竖屏内容在横屏最大化下必有黑边，不符自适应要求）；
## 初始位置按可用工作区（扣任务栏）居中。headless 无窗口语义，全部跳过。
## 消费方一律经 preload 常量引用（不依赖编辑器类名缓存，-s 工具脚本/CI 可直跑）。
extends RefCounted

const ASPECT := 9.0 / 16.0
const MIN_W := 324
const MIN_H := 576
## 初始窗口（逻辑像素），进入游戏时套用并居中
const DEFAULT_SIZE := Vector2i(594, 1056)
## 最大化过渡稳定等待帧数（Windows 切换跨多帧，期间转换会与还原尺寸竞争）
const SETTLE_FRAMES := 20

## 重入保护：吸附自身触发的 size_changed 不再进 snap；转换协程互斥
static var _snapping := false
static var _converting := false


## 接管窗口：设最小尺寸/初始尺寸、挂吸附、居中。整个游戏只应调用一次（入口场景）。
static func setup(win: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	win.min_size = Vector2i(MIN_W, MIN_H)
	win.size = DEFAULT_SIZE
	win.size_changed.connect(func() -> void: snap(win))
	center(win)


## 居中到当前屏幕可用工作区（扣任务栏），并钳入边界
static func center(win: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if win.get_tree() != null:
		await win.get_tree().process_frame
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var pos := usable.position + (usable.size - win.size) / 2
	win.position = Vector2i(pos)
	_clamp_into(win, usable)


## 吸附：最大化/全屏 → 等过渡稳定后转为最大 9:16 窗口；普通窗口 → 滞回纠正比例
static func snap(win: Window) -> void:
	if DisplayServer.get_name() == "headless" or _snapping:
		return
	if win.mode == Window.MODE_MAXIMIZED or win.mode == Window.MODE_FULLSCREEN:
		_settle_convert(win)
		return
	_snapping = true
	# 滞回吸附：偏差 >2px 才纠正，防 resize 事件自激；位置钳入工作区（防底边出屏裁内容）
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var size := win.size
	var target_h := int(round(float(size.x) / ASPECT))
	target_h = mini(target_h, usable.size.y - 16)
	if absi(target_h - size.y) > 2:
		var target_w := int(round(float(target_h) * ASPECT))
		win.size = Vector2i(maxi(MIN_W, target_w), maxi(MIN_H, target_h))
	_clamp_into(win, usable)
	_snapping = false


## 最大化/全屏处理：等过渡稳定（期间用户手动还原则中止），再转最大 9:16 窗口居中
static func _settle_convert(win: Window) -> void:
	if _converting:
		return
	_converting = true
	for i in SETTLE_FRAMES:
		if not is_instance_valid(win) or win.get_tree() == null:
			_converting = false
			return
		await win.get_tree().process_frame
		if win.mode != Window.MODE_MAXIMIZED and win.mode != Window.MODE_FULLSCREEN:
			_converting = false
			return
	_snapping = true
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var fit_h: int = usable.size.y - 16
	var fit_w: int = int(round(float(fit_h) * ASPECT))
	if fit_w > usable.size.x:
		fit_w = usable.size.x
		fit_h = int(round(float(fit_w) / ASPECT))
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(maxi(MIN_W, fit_w), maxi(MIN_H, fit_h))
	var pos := usable.position + (usable.size - win.size) / 2
	win.position = Vector2i(pos)
	_snapping = false
	_converting = false


static func _clamp_into(win: Window, usable: Rect2i) -> void:
	var pos := win.position
	pos.y = mini(pos.y, usable.position.y + usable.size.y - win.size.y)
	pos.y = maxi(pos.y, usable.position.y)
	pos.x = mini(pos.x, usable.position.x + usable.size.x - win.size.x)
	pos.x = maxi(pos.x, usable.position.x)
	win.position = pos
