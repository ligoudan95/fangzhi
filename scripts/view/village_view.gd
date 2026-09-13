## doc: 05 §2（建筑全表）/ §4（派遣）/ 17 §1（页面地图）
## 村落主场景（View）：斜 45° 单屏村落——建筑网格布局、点击进入面板。
## 建筑数据来自 Building 表；等级从存档读取；升级消耗材料+灵晶。
## View 零业务规则：全部决策在 GameSession/Logic。
extends Control

signal building_selected(building_id: int)

const BUILDING_DEFS := [
	{"id": 1, "name": "议事堂", "col": 2, "row": 0},
	{"id": 2, "name": "民居", "col": 1, "row": 0},
	{"id": 3, "name": "兽栏", "col": 3, "row": 0},
	{"id": 4, "name": "灵田", "col": 0, "row": 1},
	{"id": 5, "name": "矿场", "col": 1, "row": 1},
	{"id": 6, "name": "城墙", "col": 2, "row": 1},
	{"id": 7, "name": "锻造炉", "col": 3, "row": 1},
	{"id": 8, "name": "药庐", "col": 0, "row": 2},
	{"id": 9, "name": "仓库", "col": 1, "row": 2},
	{"id": 10, "name": "集市", "col": 2, "row": 2},
]

var _session: Node
var _selected_id := 0
var _building_buttons: Dictionary = {}

@onready var building_grid: GridContainer = $BuildingGrid
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_title: Label = $InfoPanel/VBox/InfoTitle
@onready var info_level: Label = $InfoPanel/VBox/InfoLevel
@onready var upgrade_button: Button = $InfoPanel/VBox/UpgradeButton
@onready var close_button: Button = $InfoPanel/VBox/CloseButton


func setup(session: Node) -> void:
	_session = session
	_build_grid()


func _build_grid() -> void:
	for child in building_grid.get_children():
		child.queue_free()
	_building_buttons.clear()
	for def in BUILDING_DEFS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(200, 140)
		btn.text = "%s\nLv%d" % [String(def.name), _get_level(int(def.id))]
		btn.add_theme_font_size_override("font_size", 28)
		btn.pressed.connect(_on_building_pressed.bind(int(def.id)))
		building_grid.add_child(btn)
		_building_buttons[int(def.id)] = btn


func _get_level(building_id: int) -> int:
	if _session == null:
		return 0
	for b in _session.data.village.buildings:
		if int(b.buildingId) == building_id:
			return int(b.level)
	return 0


func _on_building_pressed(building_id: int) -> void:
	_selected_id = building_id
	var def := _find_def(building_id)
	if def.is_empty():
		return
	info_title.text = String(def.name)
	info_level.text = "当前等级 %d" % _get_level(building_id)
	upgrade_button.text = "升级（灵晶 %d）" % _upgrade_cost(building_id)
	info_panel.visible = true
	building_selected.emit(building_id)


func _find_def(building_id: int) -> Dictionary:
	for def in BUILDING_DEFS:
		if int(def.id) == building_id:
			return def
	return {}


func _upgrade_cost(building_id: int) -> int:
	# Building 表的 upgradeCostBase + upgradeCostStep × 当前等级
	for b in _session._tables.get("Building", []):
		if int(b.buildingId) == building_id:
			var level := _get_level(building_id)
			return int(b.upgradeCostBase) + int(b.upgradeCostStep) * level
	return 0


func _on_upgrade_pressed() -> void:
	if _session == null or _selected_id == 0:
		return
	var cost := _upgrade_cost(_selected_id)
	if int(_session.data.wallet.spiritCrystal) < cost:
		info_level.text = "灵晶不足（需 %d）" % cost
		return
	_session.data.wallet.spiritCrystal = int(_session.data.wallet.spiritCrystal) - cost
	# 升级建筑
	var found := false
	for b in _session.data.village.buildings:
		if int(b.buildingId) == _selected_id:
			b.level = int(b.level) + 1
			found = true
			break
	if not found:
		_session.data.village.buildings.append(
			{"buildingId": _selected_id, "level": 1, "damagedUntilUtcSec": 0}
		)
	_session.save_game()
	_on_building_pressed(_selected_id)
	_build_grid()


func _on_close_pressed() -> void:
	info_panel.visible = false
	_selected_id = 0
