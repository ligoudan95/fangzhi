## doc: 15 §4
## 存档服务测试：往返/generation/checksum/恢复/迁移/导入导出。
## 用独立 user://save_test/ 目录，不污染真实存档。
extends GdUnitTestSuite

const SAVE_SCRIPT: GDScript = preload("res://scripts/infra/save_service.gd")
const TEST_DIR: String = "user://save_test/"

var _svc


func before_test() -> void:
	_svc = SAVE_SCRIPT.new()
	_svc.set_base_dir(TEST_DIR)
	_cleanup()


func after_test() -> void:
	_cleanup()
	_svc.free()


func _cleanup() -> void:
	for slot in ["auto", "manual1", "manual2", "manual3"]:
		for suffix in ["", ".bak", ".tmp"]:
			var path: String = TEST_DIR + slot + ".json" + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func _new_state() -> Dictionary:
	return GameStateFactory.create_new(1700000000, 987654321)


func test_roundtrip_and_generation() -> void:
	var save1: Dictionary = _svc.save_slot("manual1", _new_state())
	assert_bool(save1.ok).is_true()
	assert_int(save1.generation).is_equal(0)
	var loaded: Dictionary = _svc.load_slot("manual1")
	assert_bool(loaded.ok).is_true()
	assert_int(loaded.generation).is_equal(0)
	assert_str(String(loaded.data.meta.saveId)).is_equal("1700000000_987654321")
	assert_int(loaded.data.rng.streams.size()).is_equal(5)
	var save2: Dictionary = _svc.save_slot("manual1", loaded.data)
	assert_int(save2.generation).is_equal(1)


func test_checksum_tamper_detected_and_recovers_from_bak() -> void:
	_svc.save_slot("manual1", _new_state())
	# 第二代写成功后 .bak 保留上一代
	_svc.save_slot("manual1", _new_state())
	var main_path: String = TEST_DIR + "manual1.json"
	assert_bool(FileAccess.file_exists(main_path + ".bak")).is_true()
	# 篡改主档内容
	var f := FileAccess.open(main_path, FileAccess.WRITE)
	f.store_string('{"version":1,"generation":9,"checksum":"bad","data":{}}')
	f.close()
	var loaded: Dictionary = _svc.load_slot("manual1")
	assert_bool(loaded.ok).is_true()
	assert_str(loaded.recoveredFrom).is_equal(".bak")


func test_future_version_rejected() -> void:
	var path: String = TEST_DIR + "manual2.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"version":99,"generation":0,"checksum":"x","data":{}}')
	f.close()
	var loaded: Dictionary = _svc.load_slot("manual2")
	assert_bool(loaded.ok).is_false()
	assert_str(loaded.reason).contains("未来版本")


func test_v0_migration() -> void:
	var path: String = TEST_DIR + "manual3.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"pets":[],"player":{"realmId":1}}')
	f.close()
	var loaded: Dictionary = _svc.load_slot("manual3")
	assert_bool(loaded.ok).is_true()
	assert_int(int(loaded.data.player.realmId)).is_equal(1)
	assert_bool(loaded.data.settlement.cursors.has("beastTideUtcSec")).is_true()


func test_export_import_roundtrip() -> void:
	_svc.save_slot("auto", _new_state())
	var out_path: String = TEST_DIR + "export.json"
	assert_bool(_svc.export_slot("auto", out_path)).is_true()
	var imported: Dictionary = _svc.import_slot("manual2", out_path)
	assert_bool(imported.ok).is_true()
	var loaded: Dictionary = _svc.load_slot("manual2")
	assert_bool(loaded.ok).is_true()
	assert_str(String(loaded.data.meta.saveId)).is_equal("1700000000_987654321")


func test_import_rejects_tampered() -> void:
	_svc.save_slot("auto", _new_state())
	var out_path: String = TEST_DIR + "export.json"
	_svc.export_slot("auto", out_path)
	var f := FileAccess.open(out_path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	f = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(text.replace('"wallet"', '"wallet_x"'))
	f.close()
	var imported: Dictionary = _svc.import_slot("manual2", out_path)
	# 键改名 → checksum 不符（或 schema 缺键），二选一都必须拒绝
	assert_bool(imported.ok or _svc.load_slot("manual2").ok).is_false()


func test_list_and_delete() -> void:
	_svc.save_slot("auto", _new_state())
	var slots: Array[Dictionary] = _svc.list_slots()
	assert_int(slots.size()).is_equal(4)
	assert_bool(slots[0].exists).is_true()
	assert_int(slots[0].version).is_equal(1)
	assert_bool(_svc.delete_slot("auto")).is_true()
	assert_bool(_svc.load_slot("auto").ok).is_false()
