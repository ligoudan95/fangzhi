## doc: 11 §7 / 13 §8
## 音频服务（Autoload：Audio）——五总线：BGM / Amb / SFX_Battle / SFX_Work / UI。
## M6 最小实装：BGM 单通道 + SFX 池化播放；资产缺失时告警并返回失败（外部交付门禁，
## docs/14 台账跟踪）。优先级抢占（11 §4 掉宝音）随正式音频资产接入。
extends Node

const BUS_BGM: StringName = &"BGM"
const BUS_AMB: StringName = &"Amb"
const BUS_SFX_BATTLE: StringName = &"SFX_Battle"
const BUS_SFX_WORK: StringName = &"SFX_Work"
const BUS_UI: StringName = &"UI"

const SFX_POOL_SIZE: int = 8

var _bgm_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = String(BUS_BGM)
	add_child(_bgm_player)
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = String(BUS_SFX_BATTLE)
		add_child(player)
		_sfx_pool.append(player)


## BGM：循环播放；切曲淡出旧曲（docs/11 §7）。资产缺失返回 false 不崩溃。
func play_bgm(path: String, fade_sec: float = 0.0) -> bool:
	var stream := _load_stream(path)
	if stream == null:
		return false
	if fade_sec > 0.0 and _bgm_player.playing:
		var out := create_tween()
		out.tween_property(_bgm_player, "volume_db", -60.0, fade_sec)
		out.tween_callback(_start_bgm.bind(stream))
		return true
	_start_bgm(stream)
	return true


func stop_bgm(fade_sec: float = 0.0) -> void:
	if fade_sec <= 0.0:
		_bgm_player.stop()
		return
	var tween := create_tween()
	tween.tween_property(_bgm_player, "volume_db", -60.0, fade_sec)
	tween.tween_callback(_bgm_player.stop)


## SFX 播放：池化取空闲通道；总线可指定。返回是否成功发声。
func play_sfx(path: String, bus: StringName = BUS_SFX_BATTLE) -> bool:
	var player := _acquire_sfx()
	if player == null:
		return false
	var stream := _load_stream(path)
	if stream == null:
		player.stop()
		return false
	player.bus = String(bus)
	player.stream = stream
	player.play()
	return true


func _start_bgm(stream: AudioStream) -> void:
	_bgm_player.stream = stream
	_bgm_player.volume_db = 0.0
	_bgm_player.play()


func _acquire_sfx() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	# 全忙：顶替最旧（首通道），简化版抢占
	return _sfx_pool[0]


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Audio: 音频资产不存在（外部交付门禁，docs/14）：%s" % path)
		return null
	var stream: AudioStream = ResourceLoader.load(path)
	if stream == null:
		push_warning("Audio: 资源不是音频流：%s" % path)
	return stream
