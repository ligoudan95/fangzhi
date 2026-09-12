## doc: 10 §8.1 / 13 §3
## 战斗事件回放器（纯逻辑 RefCounted）：按事件类型的基础时长吐出结构化事件，
## 支持 1x/2x 提速与跳过；与 BattlePlayback 同 API 口径（tick/skip/is_done/finished 恰好一次）。
## 只消费引擎已发生事实，不产生随机、不改数值。
class_name BattleEventPlayback
extends RefCounted

## 播完（正常推进或跳过）恰好发一次
signal finished

## 各事件基础时长（秒）：cast 前摇留白 / hit 密集 / death 收束
const BASE_INTERVAL: Dictionary = {
	"start": 0.5,
	"round": 0.25,
	"cast": 0.4,
	"hit": 0.12,
	"dodge": 0.1,
	"heal": 0.18,
	"shield": 0.18,
	"buff": 0.12,
	"death": 0.35,
	"sub": 0.3,
	"cap": 0.9,
	"end": 0.5,
}

var speed: float = 1.0

var _events: Array = []
var _index: int = 0
var _acc: float = 0.0
var _notified: bool = false


func _init(events: Array) -> void:
	_events = events


func is_done() -> bool:
	return _index >= _events.size()


## 推进 delta 秒，返回本帧应应用的事件（0..n；倍速越高同帧越多）
func tick(delta: float) -> Array:
	if is_done():
		_notify_if_done()
		return []
	_acc += delta
	var out: Array = []
	while not is_done() and _acc >= _interval_at(_index) / speed:
		_acc -= _interval_at(_index) / speed
		out.append(_events[_index])
		_index += 1
	_notify_if_done()
	return out


## 跳过：返回全部剩余事件并立即结束
func skip() -> Array:
	var out: Array = []
	while not is_done():
		out.append(_events[_index])
		_index += 1
	_notify_if_done()
	return out


func remaining() -> int:
	return _events.size() - _index


func _interval_at(index: int) -> float:
	var kind := String(_events[index].get("t", ""))
	return float(BASE_INTERVAL.get(kind, 0.2))


func _notify_if_done() -> void:
	if is_done() and not _notified:
		_notified = true
		finished.emit()
