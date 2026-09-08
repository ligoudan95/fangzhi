## doc: 13 §3（battle.tscn 只消费事件队列）/ §13 D11-12
## 战斗演出回放器——纯逻辑（RefCounted）：按基础节奏吐出行、支持 1x/2x 提速、
## 跳过直接冲线；v0 事件队列即引擎日志流（docs/13 允许文本演出），
## 结构化事件（Dictionary）随正式动画（10 文档）接入时再替换数据源。
class_name BattlePlayback
extends RefCounted

## 播完（无论正常推进还是跳过）恰好发一次
signal finished

const BASE_INTERVAL: float = 0.30

var speed: float = 1.0

var _lines: Array = []
var _index: int = 0
var _acc: float = 0.0
var _notified: bool = false


func _init(lines: Array) -> void:
	_lines = lines


func is_done() -> bool:
	return _index >= _lines.size()


## 推进 delta 秒，返回本帧应显示的新行（0..n 行；倍速越高同帧吐出越多）
func tick(delta: float) -> Array:
	if is_done():
		_notify_if_done()
		return []
	_acc += delta
	var interval := BASE_INTERVAL / speed
	var out: Array = []
	while not is_done() and _acc >= interval:
		_acc -= interval
		out.append(String(_lines[_index]))
		_index += 1
	_notify_if_done()
	return out


## 跳过：返回全部剩余行并立即结束
func skip() -> Array:
	var out: Array = []
	while not is_done():
		out.append(String(_lines[_index]))
		_index += 1
	_notify_if_done()
	return out


func remaining() -> int:
	return _lines.size() - _index


func _notify_if_done() -> void:
	if is_done() and not _notified:
		_notified = true
		finished.emit()
