## doc: 15 §3
## 存档信封与 schema v1 结构校验（infra，纯校验不含业务规则）。
class_name SaveSchema
extends RefCounted

const VERSION: int = 1
const DATA_TOP_KEYS: Array[String] = [
	"meta",
	"player",
	"wallet",
	"pets",
	"equipment",
	"village",
	"settlement",
	"rng",
]
const CURSOR_KEYS: Array[String] = [
	"cultivationUtcSec",
	"patrolUtcSec",
	"villageProductionUtcSec",
	"beastTideUtcSec",
]


## 返回 "" 表示通过；否则为错误原因
static func validate_envelope(envelope: Dictionary) -> String:
	if (
		not envelope.has("version")
		or not envelope.has("generation")
		or not envelope.has("checksum")
		or not envelope.has("data")
	):
		return "信封缺 version/generation/checksum/data"
	if int(envelope.version) != VERSION:
		return "版本不符：file=%d current=%d" % [int(envelope.version), VERSION]
	if int(envelope.generation) < 0:
		return "generation 不能为负"
	if String(envelope.checksum).is_empty():
		return "checksum 为空"
	var data: Dictionary = envelope.data
	for key in DATA_TOP_KEYS:
		if not data.has(key):
			return "data 缺顶层键 %s" % key
	var meta: Dictionary = data.meta
	for key in ["saveId", "createdAtUtcSec", "updatedAtUtcSec", "lastObservedUtcSec"]:
		if not meta.has(key):
			return "data.meta 缺 %s" % key
	if int(meta.lastObservedUtcSec) < 0 or int(meta.createdAtUtcSec) < 0:
		return "meta 时间戳为负"
	var cursors: Dictionary = data.settlement.cursors
	for key in CURSOR_KEYS:
		if not cursors.has(key):
			return "settlement.cursors 缺 %s" % key
		if int(cursors[key]) < 0:
			return "游标 %s 为负" % key
	if not data.rng.has("rootSeed") or not data.rng.has("streams"):
		return "rng 结构不完整"
	return ""
