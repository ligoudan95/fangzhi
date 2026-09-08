## doc: 13 §5 / 07 §3
## 配置服务（Autoload：Config）——启动加载 res://resources/config/*.json。
## 数值唯一来源：tables/*.csv → npm run export → npm run sync:godot → resources/config/；
## 加载后只读，运行时禁止改表数据（铁律）。首包表先行，荒域表懒加载（后续分包）。
## 表形状：GlobalConst 为键值字典，其余 10 张为行数组（docs/12）。
extends Node

const CONFIG_DIR: String = "res://resources/config/"

var _tables: Dictionary = {}
var _g: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	load_all()


## 加载全部 JSON 表（幂等；headless 测试可跳过 Autoload 手动调用）
func load_all() -> void:
	if _loaded:
		return
	var dir := DirAccess.open(CONFIG_DIR)
	if dir == null:
		push_error("ConfigService: 缺少 %s——先执行 npm run sync:godot 导表回填" % CONFIG_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.get_extension() == "json":
			var parsed: Variant = _parse(CONFIG_DIR + file_name)
			if parsed != null:
				_tables[file_name.get_basename()] = parsed
		file_name = dir.get_next()
	dir.list_dir_end()
	if _tables.is_empty():
		push_error("ConfigService: %s 下没有 JSON 表" % CONFIG_DIR)
		return
	var gc: Variant = _tables.get("GlobalConst")
	_g = gc if gc is Dictionary else {}
	_loaded = true


## 取原始表：GlobalConst 返回字典，其余返回行数组；无表返回 null 并报错
func get_table(table_name: String) -> Variant:
	if _tables.has(table_name):
		return _tables[table_name]
	push_error("ConfigService: 表不存在 %s" % table_name)
	return null


## 全部已加载原始表（视图/装配层组战斗局用）
func get_all() -> Dictionary:
	return _tables


## 取行表的全部行（PetBase/SkillConfig 等）；GlobalConst 非行表，勿用此接口
func get_rows(table_name: String) -> Array:
	var raw: Variant = get_table(table_name)
	if raw is Array:
		return raw
	if raw != null:
		push_error("ConfigService: %s 不是行表（GlobalConst 用 get_g）" % table_name)
	return []


## 取 GlobalConst 数值常量（02 文档全局系数；JSON 数值统一按 float 返回）
func get_g(key: String) -> float:
	if _g.has(key):
		return float(_g[key])
	push_error("ConfigService: GlobalConst 缺键 %s" % key)
	return 0.0


func is_loaded() -> bool:
	return _loaded


func _parse(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ConfigService: 读不到 %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("ConfigService: JSON 解析失败 %s" % path)
	return parsed
