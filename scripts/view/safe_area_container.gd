## doc: 10 §7 / 13 §4
## 动态安全区容器：从 DisplayServer 实测安全区换算设计坐标边距（1080×1920 基准），
## 上下至少 80px（异形屏规范）；无刘海报全屏时退化为基准 80px。
## View 层节点脚本：不访问业务 Autoload、不改 Logic 状态。
extends MarginContainer

const DESIGN_SIZE := Vector2(1080.0, 1920.0)
const MIN_MARGIN_Y := 80
const MIN_MARGIN_X := 24


func _ready() -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	var window_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var scale_x := DESIGN_SIZE.x / maxf(1.0, float(window_size.x))
	var scale_y := DESIGN_SIZE.y / maxf(1.0, float(window_size.y))
	var left := int(float(safe.position.x) * scale_x)
	var top := int(float(safe.position.y) * scale_y)
	var right := int(float(window_size.x - safe.end.x) * scale_x)
	var bottom := int(float(window_size.y - safe.end.y) * scale_y)
	add_theme_constant_override("margin_left", maxi(MIN_MARGIN_X, left))
	add_theme_constant_override("margin_right", maxi(MIN_MARGIN_X, right))
	add_theme_constant_override("margin_top", maxi(MIN_MARGIN_Y, top))
	add_theme_constant_override("margin_bottom", maxi(MIN_MARGIN_Y, bottom))
