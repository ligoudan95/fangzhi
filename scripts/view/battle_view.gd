## doc: 13 §3 / §13 D11-12
## 最简战斗演出——打通「配置 → 战斗 → 结果」：Config 表 → BattleSetup 组局 →
## Battle headless 跑完 → BattlePlayback 逐行文本回放（1x/2x/跳过/重播同种子）。
## View 零业务逻辑：只消费结果日志流；重播=同种子确定性复现。
extends Control

## 演示阵容：灰岩獒(坦) + 桃夭狐(疗) + 朱羽雉(输出)，与对拍场景一致
const TEAM: Array = [[1001, 12, 900, 1], [1002, 12, 900, 1], [1005, 12, 950, 1]]

var _seed: int = 0
var _playback: BattlePlayback
var _last_result: Dictionary = {}

@onready var title_label: Label = $Margin/VBox/Title
@onready var stage_option: OptionButton = $Margin/VBox/Toolbar/StageOption
@onready var log_text: RichTextLabel = $Margin/VBox/LogScroll/LogText
@onready var result_label: Label = $Margin/VBox/Result
@onready var speed_button: Button = $Margin/VBox/Toolbar/SpeedButton


func _ready() -> void:
	_populate_stages()
	if _config() != null:
		_new_battle()


func _process(delta: float) -> void:
	if _playback == null or _playback.is_done():
		return
	for line in _playback.tick(delta):
		_append_line(line)


## 直接注入结果回放（测试/外部驱动用，不经 Config 与随机种子）
func start_result(result: Dictionary, stage_title: String = "") -> void:
	_last_result = result
	title_label.text = stage_title
	log_text.text = ""
	result_label.text = ""
	_playback = BattlePlayback.new(result.log)
	_playback.finished.connect(_show_result)
	if result.log.is_empty():
		_show_result()


func _append_line(line: String) -> void:
	log_text.text += line + "\n"


## 配置→战斗：Config 表组局，选中场次首波敌人
func _replay() -> void:
	var cfg_node := _config()
	if cfg_node == null:
		return
	var tables: Dictionary = cfg_node.get_all()
	var cfg := BattleSetup.build_cfg(tables)
	var team: Array = []
	for t in TEAM:
		team.append(BattleSetup.make_pet_input(cfg, int(t[0]), int(t[1]), int(t[2]), int(t[3])))
	var stages: Array = cfg_node.get_rows("StageConfig")
	if stages.is_empty():
		return
	var idx := maxi(0, stage_option.selected)
	var stage: Dictionary = stages[mini(idx, stages.size() - 1)]
	var group := int(stage.waves[0])
	var battle := Battle.new(cfg, team, BattleSetup.group_inputs(tables, cfg, group), _seed)
	var title := "关卡%d %s" % [int(stage.stageId), String(stage.name)]
	start_result(battle.run(), title)


func _new_battle() -> void:
	_seed = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	_replay()


func _show_result() -> void:
	if _playback == null:
		return
	if result_label.text.is_empty():
		result_label.text = "%s · %d 回合" % [_outcome_cn(), int(_last_result.get("rounds", 0))]


func _outcome_cn() -> String:
	match String(_last_result.get("outcome", "")):
		"victory":
			return "胜利"
		"defeat":
			return "失败"
		"captured":
			return "捕捉成功"
		_:
			return "超时判负"


## Autoload 在 headless 脚本模式下不存在（测试环境）；运行时经 /root/Config
func _config() -> Node:
	return get_node_or_null("/root/Config")


func _populate_stages() -> void:
	var cfg_node := _config()
	if cfg_node == null:
		stage_option.add_item("（测试模式）")
		return
	for row in cfg_node.get_rows("StageConfig"):
		stage_option.add_item("%d·%s" % [int(row.stageId), String(row.name)])


func _on_speed_pressed() -> void:
	if _playback == null:
		return
	_playback.speed = 2.0 if _playback.speed == 1.0 else 1.0
	speed_button.text = "2x" if _playback.speed == 2.0 else "1x"


func _on_skip_pressed() -> void:
	if _playback == null:
		return
	for line in _playback.skip():
		_append_line(line)


func _on_replay_pressed() -> void:
	_replay()


func _on_new_battle_pressed() -> void:
	_new_battle()
