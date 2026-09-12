## doc: 15 §3.3
## 存档迁移链（infra）：严格 n→n+1 注册表；发布后的迁移函数不得重写，只能追加。
class_name SaveMigrations
extends RefCounted

const CURRENT_VERSION: int = 1


## 迁移到当前版本；返回 {ok, envelope, fromVersion, reason}
## v0 定义：无信封的裸 data 字典（占位时期的 legacy 形态）
static func migrate(input: Dictionary) -> Dictionary:
	var envelope := input.duplicate(true)
	var version := 0
	if envelope.has("version"):
		version = int(envelope.version)
	if version > CURRENT_VERSION:
		return {"ok": false, "envelope": {}, "fromVersion": version, "reason": "未来版本拒绝读取"}
	while version < CURRENT_VERSION:
		var step := _step(str(version), envelope)
		if not step.ok:
			return {
				"ok": false,
				"envelope": {},
				"fromVersion": version,
				"reason": "迁移 %s 失败：%s" % [version, String(step.reason)],
			}
		envelope = step.envelope
		version += 1
	return {"ok": true, "envelope": envelope, "fromVersion": version - 1, "reason": ""}


static func _step(from_version: String, envelope: Dictionary) -> Dictionary:
	match from_version:
		"0":
			return _migrate_0_to_1(envelope)
		_:
			return {"ok": false, "envelope": {}, "reason": "无 %s 迁移函数" % from_version}


## v0（裸 data）→ v1（信封 + 补默认容器；不覆盖已有字段）。
## infra 不得引用 logic：此处内联最小默认容器，形状与 logic 层新档工厂 v1 保持一致。
static func _migrate_0_to_1(raw: Dictionary) -> Dictionary:
	var data: Dictionary = raw.get("data", raw).duplicate(true)
	if not data.has("meta"):
		data["meta"] = {
			"saveId": "migrated",
			"createdAtUtcSec": 0,
			"updatedAtUtcSec": 0,
			"lastObservedUtcSec": 0,
			"clockRollbackCount": 0,
		}
	if not data.has("player"):
		data["player"] = {"realmId": 1, "realmLayer": 0, "cultivation": 0}
	if not data.has("wallet"):
		data["wallet"] = {"beastShell": 0, "spiritCrystal": 0, "totemEmblem": 0}
	for list_key in ["pets"]:
		if not data.has(list_key):
			data[list_key] = []
	if not data.has("equipment"):
		data["equipment"] = {"items": [], "pityCounters": {}, "appliedSettlementIds": []}
	if not data.has("village"):
		data["village"] = {
			"population": 0,
			"buildings": [],
			"fields": [],
			"mineJobs": [],
			"recipeJobs": [],
			"petConditions": [],
			"storage": [],
		}
	if not data.has("settlement"):
		data["settlement"] = {"cursors": {}, "pendingReports": {}}
	elif not data.settlement.has("pendingReports"):
		data.settlement["pendingReports"] = {}
	var cursors: Dictionary = data.settlement.get("cursors", {})
	for cursor_key in SaveSchema.CURSOR_KEYS:
		if not cursors.has(cursor_key):
			cursors[cursor_key] = 0
	data.settlement["cursors"] = cursors
	if not data.has("rng"):
		data["rng"] = {"rootSeed": 0, "streams": []}
	var envelope := {
		"version": SaveSchema.VERSION,
		"generation": int(raw.get("generation", 0)),
		"checksum": "migrated",
		"data": data,
	}
	return {"ok": true, "envelope": envelope, "reason": ""}
