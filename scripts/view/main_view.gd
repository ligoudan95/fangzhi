## doc: 16 §2（FTUE 主场景）/ 15 §3.5 / 19 W2
## FTUE 主场景（View 装配）：标题→新档/续档→任务卡→出战/装备/灵田/保存；
## 战斗以 battle_view 覆盖层承载，完成信号回收后把事实喂给 GameSession。
## 零业务规则：全部决策在 GameSession/Logic；本类只做导航与展示。
extends Control

const GAME_SESSION_SCRIPT: GDScript = preload("res://scripts/view/game_session.gd")
const BATTLE_SCENE: PackedScene = preload("res://scenes/battle.tscn")
## 窗口适配器（docs/10 §12）：入口场景全局接管
const WINDOW_FIT: GDScript = preload("res://scripts/view/window_fit.gd")

## 装备部位显示名（EquipBase.slot）
const SLOT_NAMES := {1: "武器", 2: "防具", 3: "饰品"}

var session: Node
var _tables: Dictionary = {}
var _cfg: Dictionary = {}
var _close_timer: SceneTreeTimer

@onready var title_panel: Control = $TitlePanel
@onready var home_panel: Control = $HomePanel
@onready var battle_overlay: Control = $BattleOverlay
@onready var quest_title: Label = $HomePanel/QuestCard/VBox/QuestTitle
@onready var quest_goal: Label = $HomePanel/QuestCard/VBox/QuestGoal
@onready var story_button: Button = $HomePanel/QuestCard/VBox/StoryButton
@onready var quest_card: PanelContainer = $HomePanel/QuestCard
@onready var battle_button: Button = $HomePanel/Actions/BattleButton
@onready var equip_button: Button = $HomePanel/Actions/EquipButton
@onready var pet_button: Button = $HomePanel/Actions/PetButton
@onready var farm_button: Button = $HomePanel/Actions/FarmButton
@onready var village_button: Button = $HomePanel/Actions/VillageButton
@onready var save_button: Button = $HomePanel/Actions/SaveButton
@onready var status_label: Label = $HomePanel/StatusRow/StatusLabel
@onready var equip_panel: Control = $EquipPanel
@onready var equip_list: VBoxContainer = $EquipPanel/VBox/EquipScroll/EquipList
@onready var equip_close: Button = $EquipPanel/VBox/EquipClose
@onready var pet_panel: Control = $PetPanel
@onready var pet_list: VBoxContainer = $PetPanel/VBox/PetScroll/PetList
@onready var pet_close: Button = $PetPanel/VBox/PetClose
@onready var farm_panel: Control = $FarmPanel
@onready var farm_info: Label = $FarmPanel/VBox/FarmInfo
@onready var farm_plant: Button = $FarmPanel/VBox/FarmPlant
@onready var farm_skip: Button = $FarmPanel/VBox/FarmSkip
@onready var village_overlay: Control = $VillageOverlay
@onready var offline_report_panel: Control = $OfflineReportPanel
@onready var offline_report_text: Label = $OfflineReportPanel/VBox/ReportText
@onready var realm_panel: Control = $RealmPanel
@onready var realm_info_text: Label = $RealmPanel/VBox/InfoText
@onready var farm_close: Button = $FarmPanel/VBox/FarmClose


func _ready() -> void:
	var save_svc: Node = preload("res://scripts/infra/save_service.gd").new()
	session = GAME_SESSION_SCRIPT.new(save_svc)
	add_child(session)
	_tables = session._tables
	_cfg = BattleSetup.build_cfg(_tables)
	_apply_panel_styles()
	# 入口场景全局接管窗口：任意尺寸保持 9:16 自适应（docs/10 §12）
	WINDOW_FIT.setup(get_window())
	_show_title()


## 页签与弹窗视觉规范（docs/10 §5 岩彩暖色）：页签=暖棕底+边框按钮；弹窗=深棕底+金边，与背景拉开对比
func _apply_panel_styles() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#3a2f22")
	panel_style.border_color = Color("#c9a86a")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	for panel in [equip_panel, pet_panel, farm_panel, quest_card]:
		panel.add_theme_stylebox_override("panel", panel_style)
	var tab_buttons: Array = [
		battle_button, equip_button, pet_button, farm_button, village_button, save_button
	]
	for btn in tab_buttons:
		btn.add_theme_stylebox_override("normal", _tab_style(Color("#4a3b28"), Color("#8a744f")))
		btn.add_theme_stylebox_override("hover", _tab_style(Color("#5d4b33"), Color("#c9a86a")))
		btn.add_theme_stylebox_override("pressed", _tab_style(Color("#332918"), Color("#ffd98a")))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color("#f2e6c9"))
		btn.add_theme_color_override("font_hover_color", Color("#fff3d6"))
		btn.add_theme_color_override("font_pressed_color", Color("#ffd98a"))


func _tab_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


# ---------- 导航 ----------


func _show_title() -> void:
	title_panel.visible = true
	home_panel.visible = false
	_close_panels()
	battle_overlay.visible = false


## ESC 轻量返回栈（docs/17 §1 导航）：关掉最上层弹窗；战斗中先跳过演出
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if battle_overlay.visible and battle_overlay.get_child_count() > 0:
			battle_overlay.get_child(0)._on_skip_pressed()
			return
		_close_top_panel()


func _close_top_panel() -> void:
	for panel in [
		village_overlay, offline_report_panel, realm_panel, equip_panel, pet_panel, farm_panel
	]:
		if panel.visible:
			panel.visible = false
			return


## 自动保存（docs/15 §4 auto 槽）：关键事实落档后静默触发
func _autosave() -> void:
	session.save_game()


## 浮层互斥（docs/17 §2 弹窗优先级）：同一时刻至多一个面板打开
func _close_panels() -> void:
	equip_panel.visible = false
	pet_panel.visible = false
	farm_panel.visible = false
	village_overlay.visible = false
	offline_report_panel.visible = false
	realm_panel.visible = false


func _enter_home() -> void:
	title_panel.visible = false
	home_panel.visible = true
	_refresh_home()


func _refresh_home() -> void:
	var quests: Array = _tables.get("MainQuest", [])
	var active: Dictionary = QuestTracker.active_quest(session.data.player.quests, quests)
	if active.is_empty():
		quest_title.text = "第一章完成"
		quest_goal.text = "更多章节随版本解锁"
	else:
		quest_title.text = String(active.title)
		quest_goal.text = _goal_text(active)
	story_button.visible = not active.is_empty() and int(active.goalType) == 0
	battle_button.visible = not active.is_empty() and int(active.goalType) in [1, 2]
	var pets: int = session.data.pets.size()
	var equips: int = session.data.equipment.items.size()
	var realm: Dictionary = session.realm_info()
	status_label.text = (
		"%s · 修为 %d · 灵宠 %d · 装备 %d"
		% [String(realm.display), int(session.data.player.cultivation), pets, equips]
	)


func _goal_text(q: Dictionary) -> String:
	var texts := {
		1: "通关关卡 %d" % int(q.targetId),
		2: "捕捉灵宠（%d 只）" % int(q.count),
		3: "获得一件装备",
		4: "鉴定一件装备",
		5: "收获作物",
		6: "上阵 %d 只灵宠" % int(q.count),
	}
	return String(texts.get(int(q.goalType), "点击推进剧情"))


# ---------- 标题 ----------


func _on_new_game_pressed() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	session.new_game(now, now % 2147483647)
	session.advance_story()
	_enter_home()


func _on_continue_pressed() -> void:
	if session.load_game():
		_enter_home()
		# 回归开屏结算（docs/15 §1.5/§2）：按离线时长补结算 → 存档 → 展示报告
		var now := int(Time.get_unix_time_from_system())
		var elapsed := now - int(session.data.meta.lastObservedUtcSec)
		if elapsed > 60:
			var report: Dictionary = session.settle_offline(now)
			session.save_game()
			_refresh_home()
			_show_offline_report(elapsed, session.offline_summary_lines(report))
	else:
		_on_new_game_pressed()


## 离线结算报告（模态）：领取即关闭（奖励已按游标幂等入账并落档）
func _show_offline_report(elapsed_sec: int, lines: Array[String]) -> void:
	var hours := float(elapsed_sec) / 3600.0
	var head := "离开 %.1f 小时" % hours
	# gdformat 会把字符串内换行转义重排成真实换行——用 chr(10) 规避
	var nl := String.chr(10)
	offline_report_text.text = head + nl + nl + nl.join(lines)
	_close_panels()
	offline_report_panel.visible = true


func _on_offline_claim_pressed() -> void:
	offline_report_panel.visible = false
	_autosave()


# ---------- 任务与战斗 ----------


func _on_story_pressed() -> void:
	session.advance_story()
	_refresh_home()


## 出战：按当前任务决定关卡与捕捉模式；胜利→关卡进度+掉宝；captured→捕捉进度
func _on_battle_pressed() -> void:
	_close_panels()
	var quests: Array = _tables.get("MainQuest", [])
	var active: Dictionary = QuestTracker.active_quest(session.data.player.quests, quests)
	var stage_id := 1
	var capture := false
	if not active.is_empty():
		if int(active.goalType) == 1:
			stage_id = int(active.targetId)
		elif int(active.goalType) == 2:
			capture = true
			stage_id = _latest_unlocked_stage()
	var stage: Dictionary = _find_stage(stage_id)
	if stage.is_empty():
		return
	# 出战队 = 玩家阵伍（真实资质/性格/等级/突破）；空阵伍回退序章演示三兽（docs/16）
	var team: Array = session.build_battle_team()
	var group := int(stage.waves[0])
	var battle := Battle.new(
		_cfg,
		team,
		BattleSetup.group_inputs(_tables, _cfg, group),
		session.data.rng.rootSeed,
		{"capture": capture}
	)
	_open_battle_overlay(battle.run(), stage, capture)


func _open_battle_overlay(result: Dictionary, stage: Dictionary, capture: bool) -> void:
	for child in battle_overlay.get_children():
		child.queue_free()
	var view: Control = BATTLE_SCENE.instantiate()
	battle_overlay.add_child(view)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.start_result(result, "关卡%d %s" % [int(stage.stageId), String(stage.name)])
	view.battle_finished.connect(_on_battle_finished.bind(stage, capture))
	battle_overlay.visible = true


func _on_battle_finished(result: Dictionary, stage: Dictionary, capture: bool) -> void:
	if String(result.outcome) == "victory":
		session.on_stage_cleared(int(stage.stageId))
		if int(stage.dropCount) > 0:
			session.settle_stage_drop(stage, int(session.data.rng.rootSeed))
	elif capture and String(result.outcome) == "captured":
		# 捕捉等级跟随敌方野性等级（docs/04：捉来的兽保有野性）
		session.on_pet_captured(
			int(result.get("capturedPetId", 1003)), _enemy_level_of_stage(stage)
		)
		session.on_party_changed(session.party().size())
	_refresh_home()
	_autosave()
	_close_timer = get_tree().create_timer(1.2)
	_close_timer.timeout.connect(func() -> void: battle_overlay.visible = false)


func _find_stage(stage_id: int) -> Dictionary:
	for s in _tables.get("StageConfig", []):
		if int(s.stageId) == stage_id:
			return s
	return {}


func _latest_unlocked_stage() -> int:
	var max_id := 1
	var cleared: Dictionary = session.data.player.quests.counters
	for s in _tables.get("StageConfig", []):
		var sid := int(s.stageId)
		if cleared.get("g1:t%d" % sid, 0) > 0 and sid > max_id:
			max_id = sid
	return mini(max_id, 5)


# ---------- 装备 ----------


## 灵宠面板（docs/04 §2/§3）：资质五维+性格+突破阶段展示
func _on_pet_pressed() -> void:
	_close_panels()
	_refresh_pet_list()
	pet_panel.visible = true


func _refresh_pet_list() -> void:
	for child in pet_list.get_children():
		pet_list.remove_child(child)
		child.free()
	$PetPanel/VBox/PetHeader.text = "灵宠（阵伍 %d/3）" % session.party().size()
	var pets: Array = session.data.pets
	if pets.is_empty():
		var empty := Label.new()
		empty.text = "暂无灵宠——出战捕捉"
		empty.add_theme_font_size_override("font_size", 30)
		pet_list.add_child(empty)
		return
	for pet in pets:
		var detail: Dictionary = session.get_pet_detail(int(pet.instanceId))
		if String(detail.get("error", "")) != "":
			continue
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 27)
		var apt: Dictionary = detail.aptitudes
		info.text = (
			"%s%s Lv%d/%d [%s]  攻%d 防%d 体%d 速%d 灵%d"
			% [
				"【阵】" if bool(detail.inParty) else "",
				String(detail.name),
				int(detail.level),
				int(detail.levelCap),
				String(detail.nature),
				int(apt.atk),
				int(apt.def),
				int(apt.hp),
				int(apt.spd),
				int(apt.mag),
			]
		)
		card.add_child(info)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		var party_btn := Button.new()
		party_btn.text = "下阵" if bool(detail.inParty) else "上阵"
		party_btn.add_theme_font_size_override("font_size", 26)
		party_btn.pressed.connect(_on_pet_party_pressed.bind(int(pet.instanceId)))
		actions.add_child(party_btn)
		var feed_btn := Button.new()
		feed_btn.text = "喂养（%d修为）" % int(detail.feedCost)
		feed_btn.add_theme_font_size_override("font_size", 26)
		feed_btn.pressed.connect(_on_pet_feed_pressed.bind(int(pet.instanceId)))
		actions.add_child(feed_btn)
		var brk_btn := Button.new()
		brk_btn.text = "突破"
		brk_btn.add_theme_font_size_override("font_size", 26)
		brk_btn.pressed.connect(_on_pet_break_pressed.bind(int(pet.instanceId)))
		actions.add_child(brk_btn)
		card.add_child(actions)
		pet_list.add_child(card)


func _on_pet_party_pressed(instance_id: int) -> void:
	var res: Dictionary = session.toggle_party(instance_id)
	session.on_party_changed(int(res.size))
	_refresh_pet_list()


func _on_pet_feed_pressed(instance_id: int) -> void:
	session.feed_pet(instance_id)
	_refresh_pet_list()
	_refresh_home()
	_autosave()


func _on_pet_break_pressed(instance_id: int) -> void:
	session.breakthrough_pet(instance_id)
	_refresh_pet_list()
	_refresh_home()
	_autosave()


func _on_pet_close_pressed() -> void:
	pet_panel.visible = false


func _on_equip_pressed() -> void:
	_close_panels()
	_refresh_equip_list()
	equip_panel.visible = true


func _refresh_equip_list() -> void:
	for child in equip_list.get_children():
		child.queue_free()
	var items: Array = session.data.equipment.items
	if items.is_empty():
		var empty := Label.new()
		empty.text = "暂无装备——出战获取"
		equip_list.add_child(empty)
		return
	for item in items:
		var view: Dictionary = session.equipment_view(String(item.instanceId))
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 27)
		if not bool(view.identified):
			info.text = "未鉴定装备"
		else:
			var worn := ""
			if int(view.wornBy) > 0:
				var pet_name := ""
				for pet in session.data.pets:
					if int(pet.instanceId) == int(view.wornBy):
						pet_name = String(session.get_pet_detail(int(view.wornBy)).name)
						break
				worn = "  【%s 穿戴】" % pet_name
			var cost: Dictionary = EquipEnhance.enhance_cost(int(view.enhanceLevel))
			var head := (
				"%s %s+%d  主%s+%d 词条%d%s"
				% [
					String(SLOT_NAMES.get(int(view.slot), "?")),
					"品%d" % int(view.quality),
					int(view.enhanceLevel),
					String(view.mainStat),
					int(view.mainValue),
					int(view.affixCount),
					worn,
				]
			)
			var fee := "强化费用：铁锭" + str(int(cost.metalIngot)) + " 灵晶" + str(int(cost.spiritCrystal))
			var nl := String.chr(10)
			info.text = head + nl + fee
		card.add_child(info)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		if not bool(view.identified):
			var id_btn := Button.new()
			id_btn.text = "鉴定"
			id_btn.add_theme_font_size_override("font_size", 26)
			id_btn.pressed.connect(_on_identify_pressed.bind(String(item.instanceId)))
			actions.add_child(id_btn)
		else:
			var enh_btn := Button.new()
			enh_btn.text = "强化 +%d" % (int(view.enhanceLevel) + 1)
			enh_btn.add_theme_font_size_override("font_size", 26)
			enh_btn.pressed.connect(_on_enhance_pressed.bind(String(item.instanceId)))
			actions.add_child(enh_btn)
			if int(view.wornBy) > 0:
				var off_btn := Button.new()
				off_btn.text = "卸下"
				off_btn.add_theme_font_size_override("font_size", 26)
				off_btn.pressed.connect(_on_takeoff_pressed.bind(String(item.instanceId)))
				actions.add_child(off_btn)
			else:
				var wear_btn := Button.new()
				wear_btn.text = "穿戴"
				wear_btn.add_theme_font_size_override("font_size", 26)
				wear_btn.pressed.connect(_on_wear_pressed.bind(String(item.instanceId)))
				actions.add_child(wear_btn)
		card.add_child(actions)
		equip_list.add_child(card)


func _on_identify_pressed(instance_id: String) -> void:
	session.identify_equipment(instance_id)
	_refresh_equip_list()
	_refresh_home()


## 强化（docs/08 §7.1）：锻造炉上限/材料/成功率档位在会话内判定
func _on_enhance_pressed(instance_id: String) -> void:
	var res: Dictionary = session.enhance_equipment(instance_id)
	if not bool(res.ok):
		_refresh_equip_list()
		return
	_refresh_equip_list()
	_refresh_home()


## 穿戴：默认穿给阵队首位灵宠（阵队空则第一只）
func _on_wear_pressed(instance_id: String) -> void:
	var target := 0
	var party: Array = session.party()
	if not party.is_empty():
		target = int(party[0])
	elif not session.data.pets.is_empty():
		target = int(session.data.pets[0].instanceId)
	if target > 0:
		session.wear_equipment(instance_id, target)
	_refresh_equip_list()


func _on_takeoff_pressed(instance_id: String) -> void:
	session.takeoff_equipment(instance_id)
	_refresh_equip_list()


func _on_equip_close_pressed() -> void:
	equip_panel.visible = false


# ---------- 灵田 ----------


## 村落场景（docs/05 §2）：建筑网格 + 点击升级
func _on_village_pressed() -> void:
	_close_panels()
	for child in village_overlay.get_children():
		village_overlay.remove_child(child)
		child.free()
	var village: Control = preload("res://scenes/village.tscn").instantiate()
	village_overlay.add_child(village)
	village.set_anchors_preset(Control.PRESET_FULL_RECT)
	village.setup(session)
	village_overlay.visible = true
	# 关闭按钮由 main_view 统一提供
	var back := Button.new()
	back.text = "返回"
	back.add_theme_font_size_override("font_size", 32)
	back.custom_minimum_size = Vector2(160, 72)
	back.position = Vector2(20, 20)
	back.pressed.connect(func() -> void: village_overlay.visible = false)
	village_overlay.add_child(back)


func _on_farm_pressed() -> void:
	_close_panels()
	_refresh_farm()
	farm_panel.visible = true


func _refresh_farm() -> void:
	var fields: Array = session.data.village.fields
	if fields.is_empty():
		farm_info.text = "灵田空置——播种灵谷（30 分钟成熟）"
	else:
		farm_info.text = "已播种 %d 块田" % fields.size()
	var storage: Array = session.data.village.storage
	var total := 0
	for s in storage:
		total += int(s.amount)
	farm_info.text += "\n仓库存量 %d" % total


func _on_farm_plant_pressed() -> void:
	var now := int(Time.get_unix_time_from_system())
	var slot: int = session.data.village.fields.size() + 1
	var res: Dictionary = session.plant_crop(slot, 1, now)
	if not bool(res.ok):
		farm_info.text = String(res.error)
		return
	_refresh_farm()


## 离线快进（FTUE 预教育）：结算未来 1 小时——作物成熟入库并触发收获任务
func _on_farm_skip_pressed() -> void:
	var now := int(Time.get_unix_time_from_system())
	var report: Dictionary = session.settle_offline(now + 3600)
	var lines: Array = []
	for o in report.crops.outputs:
		lines.append("收获 物品%d ×%d" % [int(o.itemId), int(o.amount)])
	farm_info.text = "；".join(lines) if not lines.is_empty() else "暂无产出"
	_refresh_farm()
	_refresh_home()


func _on_farm_close_pressed() -> void:
	farm_panel.visible = false


# ---------- 境界（docs/02 §2.2） ----------


func _on_realm_pressed() -> void:
	_close_panels()
	_refresh_realm_panel()
	realm_panel.visible = true


func _refresh_realm_panel() -> void:
	var info: Dictionary = session.realm_info()
	var nl := String.chr(10)
	realm_info_text.text = (
		"当前境界：" + String(info.display) + nl + nl + "下一层需修为 " + str(int(info.nextCost))
	)


func _on_realm_advance_pressed() -> void:
	var res: Dictionary = session.advance_realm()
	_refresh_realm_panel()
	_refresh_home()
	if not bool(res.ok):
		realm_info_text.text = String(res.reason)


func _on_realm_close_pressed() -> void:
	realm_panel.visible = false


## 关卡首波敌人的最高等级（捕捉入场等级基准）
func _enemy_level_of_stage(stage: Dictionary) -> int:
	var group_id := int(stage.waves[0])
	var max_lv := 1
	for e in _tables.get("EnemyGroup", []):
		if int(e.groupId) == group_id:
			max_lv = maxi(max_lv, int(e.level))
	return max_lv


# ---------- 保存 ----------


func _on_save_pressed() -> void:
	var ok: bool = session.save_game()
	_refresh_home()
	var suffix := " · 已保存" if ok else " · 保存失败"
	status_label.text += suffix
