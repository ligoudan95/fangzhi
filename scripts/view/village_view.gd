## doc: 05 §2（建筑全表）/ §6（矿场）/ §7（锻造/药庐）/ 17 §1（页面地图）
## 村落主场景（View）：建筑网格布局、点击进入面板（升级/开采/生产）。
## View 零业务规则：升级/开采/生产全部调 GameSession，本类只渲染结果。
extends Control

signal building_selected(building_id: int)

const BUILDING_DEFS := [
	{"id": 1, "name": "议事堂", "col": 2, "row": 0},
	{"id": 2, "name": "民居", "col": 1, "row": 0},
	{"id": 3, "name": "兽栏", "col": 3, "row": 0},
	{"id": 4, "name": "灵田", "col": 0, "row": 1},
	{"id": 5, "name": "矿场", "col": 1, "row": 1},
	{"id": 6, "name": "城墙箭塔", "col": 2, "row": 1},
	{"id": 7, "name": "锻造炉", "col": 3, "row": 1},
	{"id": 8, "name": "药庐", "col": 0, "row": 2},
	{"id": 9, "name": "仓库", "col": 1, "row": 2},
	{"id": 10, "name": "集市", "col": 2, "row": 2},
]

var _session: Node
var _selected_id := 0
var _building_buttons: Dictionary = {}

@onready var building_grid: GridContainer = $BuildingArea/BuildingGrid
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_title: Label = $InfoPanel/VBox/InfoTitle
@onready var info_level: Label = $InfoPanel/VBox/InfoLevel
@onready var action_list: VBoxContainer = $InfoPanel/VBox/ActionScroll/ActionList
@onready var upgrade_button: Button = $InfoPanel/VBox/UpgradeButton
@onready var close_button: Button = $InfoPanel/VBox/CloseButton


func _ready() -> void:
	# 与主场景弹窗同款视觉规范（docs/10 §5）：深棕底+金边
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#3a2f22")
	panel_style.border_color = Color("#c9a86a")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	info_panel.add_theme_stylebox_override("panel", panel_style)


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
	_render_actions(building_id)
	info_panel.visible = true
	building_selected.emit(building_id)


## 建筑面板内容按类型渲染（docs/05 §2/§6/§7）：升级通用；矿场=开采；锻造炉/药庐=配方生产
func _render_actions(building_id: int) -> void:
	for child in action_list.get_children():
		action_list.remove_child(child)
		child.free()
	var lines: Array[String] = ["当前等级 %d" % _get_level(building_id)]
	match building_id:
		5:  # 矿场：开采矿层（docs/05 §6）
			var slots := _mine_slots()
			var used: int = _session.data.village.mineJobs.size()
			lines.append("矿位 %d/%d" % [used, slots])
			if used < slots:
				var mine_btn := Button.new()
				mine_btn.text = "开采新矿层"
				mine_btn.add_theme_font_size_override("font_size", 30)
				mine_btn.pressed.connect(_on_mine_pressed)
				action_list.add_child(mine_btn)
		7, 8:  # 锻造炉/药庐：配方生产（docs/05 §7）
			var station := 1 if building_id == 7 else 2
			var cap := _queue_cap(building_id)
			lines.append("队列 %d/%d" % [_session.data.village.recipeJobs.size(), cap])
			for r in _session._tables.get("Recipe", []):
				if int(r.station) != station:
					continue
				var row := HBoxContainer.new()
				var label := Label.new()
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label.add_theme_font_size_override("font_size", 26)
				label.text = (
					"配方%d → 物品%d ×%d（%d分钟）"
					% [int(r.recipeId), int(r.outputItemId), int(r.outputCount), int(r.durationMin)]
				)
				row.add_child(label)
				var btn := Button.new()
				btn.text = "开始"
				btn.add_theme_font_size_override("font_size", 26)
				btn.pressed.connect(_on_craft_pressed.bind(int(r.recipeId)))
				row.add_child(btn)
				action_list.add_child(row)
	info_level.text = "\n".join(lines)


func _on_mine_pressed() -> void:
	if _session == null:
		return
	var now := int(Time.get_unix_time_from_system())
	var next_mine := _next_mine_id()
	# 派遣第一只体力充足的灵宠（docs/05 §4）；无可用宠则裸采（效率 1）
	var pets: Array = []
	for c in _session.data.village.petConditions:
		if PetDispatch.can_dispatch(c, {}):
			pets.append(int(c.petInstanceId))
			break
	var res: Dictionary = _session.assign_mine(next_mine, now, pets)
	if bool(res.ok):
		var eff := float(res.get("efficiency", 1.0))
		info_level.text = "开采矿层 %d（效率 %.0f%%）" % [int(res.slotId), eff * 100.0]
	else:
		info_level.text = String(res.error)
	_render_actions(_selected_id)


func _on_craft_pressed(recipe_id: int) -> void:
	if _session == null:
		return
	var now := int(Time.get_unix_time_from_system())
	var res: Dictionary = _session.craft(recipe_id, now)
	info_level.text = "已入队" if bool(res.ok) else String(res.error)
	_render_actions(_selected_id)


func _next_mine_id() -> int:
	# 已开采矿层顺次+1（矿层表按 mineId 升序；docs/05 §6）
	var max_id := 0
	for j in _session.data.village.mineJobs:
		max_id = maxi(max_id, int(j.mineId))
	return mini(max_id + 1, _session.data.village.mineJobs.size() + 1)


func _mine_slots() -> int:
	return BuildingEffects.mine_slots(
		_session.data.village.buildings, _session._tables.get("Building", [])
	)


func _queue_cap(building_id: int) -> int:
	return BuildingEffects.queue_cap(
		_session.data.village.buildings, building_id, _session._tables.get("Building", [])
	)


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
	var res: Dictionary = _session.upgrade_building(_selected_id)
	if not bool(res.ok):
		info_level.text = String(res.error)
		return
	_session.save_game()
	_render_actions(_selected_id)
	_build_grid()


func _on_close_pressed() -> void:
	info_panel.visible = false
	_selected_id = 0
