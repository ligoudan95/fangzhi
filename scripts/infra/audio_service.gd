## doc: 11 §x / 13 §8
## 音频服务（Autoload：Audio）——五总线：BGM / Amb / SFX_Battle / SFX_Work / UI。
## D1 仅总线常量与接口占位；播放、优先级抢占（11 §7）、BGM 懒加载随音频资产接入。
extends Node

const BUS_BGM: StringName = &"BGM"
const BUS_AMB: StringName = &"Amb"
const BUS_SFX_BATTLE: StringName = &"SFX_Battle"
const BUS_SFX_WORK: StringName = &"SFX_Work"
const BUS_UI: StringName = &"UI"


## BGM 懒加载：ResourceLoader.load_threaded_request（13 §8，资产接入后实现）
func play_bgm(path: String) -> void:
	push_warning("Audio.play_bgm 尚未实现（音频资产未接入）：%s" % path)


## SFX 播放；bus 缺省 SFX_Battle（掉宝音效优先级抢占见 11 §7，随资产接入）
func play_sfx(path: String, bus: StringName = BUS_SFX_BATTLE) -> void:
	push_warning("Audio.play_sfx 尚未实现（音频资产未接入）：%s @ %s" % [path, bus])
