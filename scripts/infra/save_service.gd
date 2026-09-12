## doc: 07 §4 / 13 §10 / 15 §3
## 存档服务（Autoload：Save）——user://save/ JSON 信封 + checksum + 迁移链 + 原子写 + 恢复。
## 只做 IO/校验/迁移调度，不含任何收益计算（结算器在 logic 层，docs/15 §3.5）。
## 只存实例（ID/等级/roll 种子），不快照配置；3 手动位 + 1 自动位。
extends Node

const SAVE_DIR: String = "user://save/"
const SAVE_VERSION: int = 1
const VALID_SLOTS: PackedStringArray = ["auto", "manual1", "manual2", "manual3"]
const SLOT_AUTO: String = "auto"
const SLOTS_MANUAL: PackedStringArray = ["manual1", "manual2", "manual3"]
const ENVELOPE_KEYS: Array[String] = ["version", "generation", "checksum", "data"]

var _base_dir: String = SAVE_DIR
var _generations: Dictionary = {}


func _ready() -> void:
	_init_dir(SAVE_DIR)


func _init_dir(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)


func set_base_dir(dir: String) -> void:
	_base_dir = dir
	_generations.clear()
	_init_dir(dir)


func slot_path(slot: String, suffix: String = "") -> String:
	return _base_dir + slot + ".json" + suffix


func _is_valid_slot(slot: String) -> bool:
	return VALID_SLOTS.has(slot)


## 原子写：tmp（flush+回读校验）→ 旧主档轮转 .bak → rename；失败不删除最后有效候选
func atomic_write(path: String, text: String) -> bool:
	var tmp_path: String = path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Save.atomic_write 打不开临时文件：%s（err=%d）" % [tmp_path, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.flush()
	f.close()
	var verify := FileAccess.open(tmp_path, FileAccess.READ)
	if verify == null or verify.get_as_text() != text:
		push_error("Save.atomic_write 回读校验失败：%s" % tmp_path)
		return false
	verify.close()
	if FileAccess.file_exists(path):
		var bak_path: String = path + ".bak"
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		if DirAccess.rename_absolute(path, bak_path) != OK:
			push_error("Save.atomic_write 轮转备份失败：%s" % bak_path)
			return false
	return DirAccess.rename_absolute(tmp_path, path) == OK


## 保存：槽位白名单 → 并发 generation → 信封+checksum → 原子写；返回 {ok, generation, reason}
func save_slot(slot: String, data: Dictionary) -> Dictionary:
	if not _is_valid_slot(slot):
		return {"ok": false, "generation": -1, "reason": "非法槽位名：%s" % slot}
	var expected := int(_generations.get(slot, -1))
	var current := _read_generation(slot_path(slot))
	if current != expected:
		return {
			"ok": false,
			"generation": current,
			"reason": "generation 冲突：file=%d mem=%d" % [current, expected]
		}
	var envelope_data := data.duplicate(true)
	var generation := expected + 1
	## checksum：先 JSON 往返再规范化——与 load 侧看到完全相同的类型表示（docs/15 §3.1）
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(envelope_data))
	var checksum := _checksum_text(
		_canonicalize({"version": SAVE_VERSION, "generation": generation, "data": roundtrip})
	)
	var envelope := {
		"version": SAVE_VERSION,
		"generation": generation,
		"checksum": checksum,
		"data": envelope_data,
	}
	var text := JSON.stringify(envelope)
	if not atomic_write(slot_path(slot), text):
		return {"ok": false, "generation": expected, "reason": "原子写失败"}
	_generations[slot] = generation
	return {"ok": true, "generation": generation, "reason": ""}


## 读取：主档 → .bak → .tmp；checksum/结构校验；v0 迁移；损坏主档留 .corrupt 证
func load_slot(slot: String) -> Dictionary:
	if not _is_valid_slot(slot):
		return {
			"ok": false,
			"data": {},
			"generation": -1,
			"recoveredFrom": "",
			"migratedFrom": -1,
			"reason": "非法槽位名：%s" % slot
		}
	var fail := func(reason: String) -> Dictionary:
		return {
			"ok": false,
			"data": {},
			"generation": -1,
			"recoveredFrom": "",
			"migratedFrom": -1,
			"reason": reason
		}
	var candidates: Array[String] = ["", ".bak", ".tmp"]
	var first_error := "槽位不存在"
	var main_existed := false
	for suffix in candidates:
		var path := slot_path(slot, suffix)
		if not FileAccess.file_exists(path):
			continue
		if suffix == "":
			main_existed = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null or not (parsed is Dictionary):
			first_error = "JSON 解析失败（%s）" % suffix
			continue
		var envelope: Dictionary = parsed
		if int(envelope.get("version", 0)) > SaveMigrations.CURRENT_VERSION:
			return fail.call("未来版本拒绝读取：file=%d" % int(envelope.version))
		if int(envelope.get("version", 0)) < SaveMigrations.CURRENT_VERSION:
			var mig := SaveMigrations.migrate(envelope)
			if not bool(mig.ok):
				return fail.call(String(mig.reason))
			envelope = mig.envelope
			# 迁移产物落盘（备份由调用方/上层策略处理）
			if not _write_envelope(slot, envelope):
				return fail.call("迁移结果写回失败")
		elif String(envelope.get("checksum", "")) != _envelope_checksum(envelope):
			first_error = "checksum 不符（%s）" % suffix
			continue
		var schema_error := SaveSchema.validate_envelope(envelope)
		if schema_error != "":
			first_error = "%s（%s）" % [schema_error, suffix]
			continue
		_generations[slot] = int(envelope.generation)
		if suffix != "" and main_existed:
			var main_path := slot_path(slot)
			var corrupt: String = main_path + ".corrupt.%d" % int(Time.get_unix_time_from_system())
			DirAccess.rename_absolute(main_path, corrupt)
		return {
			"ok": true,
			"data": envelope.data,
			"generation": int(envelope.generation),
			"recoveredFrom": suffix,
			"migratedFrom": -1,
			"reason": "",
		}
	return fail.call(first_error)


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in [SLOT_AUTO] + Array(SLOTS_MANUAL):
		var path := slot_path(slot)
		var info := {"slot": slot, "exists": FileAccess.file_exists(path)}
		if info.exists:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				info["version"] = int((parsed as Dictionary).get("version", 0))
				info["generation"] = int((parsed as Dictionary).get("generation", 0))
				info["updatedAt"] = int(
					((parsed as Dictionary).get("data", {}) as Dictionary).get("meta", {}).get(
						"updatedAtUtcSec", 0
					)
				)
		out.append(info)
	return out


func delete_slot(slot: String) -> bool:
	if not _is_valid_slot(slot):
		return false
	var ok := true
	for suffix in ["", ".bak", ".tmp"]:
		var path := slot_path(slot, suffix)
		if FileAccess.file_exists(path):
			ok = DirAccess.remove_absolute(path) == OK and ok
	_generations.erase(slot)
	return ok


## 导出：整份信封文本（分享/备份）；不做结算
func export_slot(slot: String, to_path: String) -> bool:
	if not _is_valid_slot(slot):
		return false
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(to_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(FileAccess.get_file_as_string(path))
	f.close()
	return true


## 导入：结构校验后原子落位；generation 沿用文件值
func import_slot(slot: String, from_path: String) -> Dictionary:
	if not _is_valid_slot(slot):
		return {"ok": false, "reason": "非法槽位名：%s" % slot}
	var read := _read_import_envelope(from_path)
	if String(read.error) != "":
		return {"ok": false, "reason": read.error}
	var envelope: Dictionary = read.envelope
	if not _write_envelope(slot, envelope):
		return {"ok": false, "reason": "写入失败"}
	_generations[slot] = int(envelope.generation)
	return {"ok": true, "reason": ""}


func _read_import_envelope(from_path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(from_path))
	if parsed == null or not (parsed is Dictionary):
		return {"envelope": {}, "error": "导入文件不是合法 JSON"}
	var envelope: Dictionary = parsed
	if int(envelope.get("version", 0)) > SaveMigrations.CURRENT_VERSION:
		return {"envelope": {}, "error": "导入文件为未来版本"}
	if int(envelope.get("version", 0)) < SaveMigrations.CURRENT_VERSION:
		var mig := SaveMigrations.migrate(envelope)
		if not bool(mig.ok):
			return {"envelope": {}, "error": String(mig.reason)}
		envelope = mig.envelope
	var schema_error := SaveSchema.validate_envelope(envelope)
	if schema_error != "":
		return {"envelope": {}, "error": schema_error}
	if (
		String(envelope.checksum) != "migrated"
		and String(envelope.checksum) != _envelope_checksum(envelope)
	):
		return {"envelope": {}, "error": "导入文件 checksum 不符"}
	return {"envelope": envelope, "error": ""}


func _write_envelope(slot: String, envelope: Dictionary) -> bool:
	return atomic_write(slot_path(slot), JSON.stringify(envelope))


## 校验用 checksum：从已解析 envelope 规范化（不含 checksum 字段自身）。
## save 侧先经 JSON 往返再规范化，两侧类型表示一致（消除 int→float 差异）。
func _envelope_checksum(envelope: Dictionary) -> String:
	return _checksum_text(
		_canonicalize(
			{
				"version": int(envelope.version),
				"generation": int(envelope.generation),
				"data": envelope.data
			}
		)
	)


func _read_generation(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("generation", -1))
	return -1


## 规范化 JSON：键递归排序、无空白、整数化浮点（int 与 JSON 解析出的 5.0 输出一致）
func _canonicalize(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return _canonicalize_dict(value as Dictionary)
		TYPE_ARRAY:
			var items: Array[String] = []
			for item in value as Array:
				items.append(_canonicalize(item))
			return "[" + ",".join(items) + "]"
		_:
			return _canonicalize_leaf(value)


func _canonicalize_dict(dict: Dictionary) -> String:
	var keys: Array = dict.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append(_json_key(str(k)) + ":" + _canonicalize(dict[k]))
	return "{" + ",".join(parts) + "}"


func _canonicalize_leaf(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return JSON.stringify(value)
		TYPE_FLOAT:
			var f := value as float
			if is_equal_approx(f, floorf(f)) and absf(f) < 9007199254740992.0:
				return str(int(f))
			return str(f)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		_:
			return str(value)


func _json_key(key: String) -> String:
	return JSON.stringify(key)


## SHA-256 小写 hex（HashingContext，headless 可用）
func _checksum_text(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()
