## doc: 07 §5 / 13 §6
## mulberry32 种子随机——与 TS 基准 src/battle/engine.ts makeRng 逐位一致。
## 对拍红线：GDScript 整数是 64 位有符号，所有运算后 & 0xFFFFFFFF 模拟 32 位
## 无符号语义；乘法用 16 位拆分防 int64 溢出（(2^32-1)^2 > int64 上限）。
class_name BattleRng
extends RefCounted

const _M: int = 0x6D2B79F5

var _a: int


func _init(seed: int) -> void:
	_a = seed & 0xFFFFFFFF


func next() -> float:
	_a = (_a + _M) & 0xFFFFFFFF
	var t := _a
	t = _mul32((t ^ (t >> 15)) & 0xFFFFFFFF, (t | 1) & 0xFFFFFFFF)
	var s := (t + _mul32((t ^ (t >> 7)) & 0xFFFFFFFF, (t | 61) & 0xFFFFFFFF)) & 0xFFFFFFFF
	t = t ^ s
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


## 32 位无符号乘法取低 32 位：b 拆高低 16 位，中间积 < 2^49 不溢出 int64
static func _mul32(a: int, b: int) -> int:
	var blo := b & 0xFFFF
	var bhi := b >> 16
	return ((a * blo) + (((a * bhi) & 0xFFFFFFFF) << 16)) & 0xFFFFFFFF
