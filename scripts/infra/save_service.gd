## doc: 07 §4 / 13 §10
## 存档服务（Autoload：Save）——user://save/ JSON + 版本迁移链 + 原子写。
## 只存实例（ID/等级/roll 种子），不快照配置；3 手动位 + 1 自动位。
## 存档结构与迁移链为 Phase 0 余项，本文件先落目录、槽位与原子写底座。
extends Node

const SAVE_DIR: String = "user://save/"
const SAVE_VERSION: int = 1
const SLOT_AUTO: String = "auto"
const SLOTS_MANUAL: PackedStringArray = ["manual1", "manual2", "manual3"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func slot_path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


## 原子写：先写临时文件再 rename，防崩溃半写（07 §4 防损）
func atomic_write(path: String, text: String) -> bool:
	var tmp_path: String = path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Save.atomic_write 打不开临时文件：%s（err=%d）" % [tmp_path, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.close()
	return DirAccess.rename_absolute(tmp_path, path) == OK
