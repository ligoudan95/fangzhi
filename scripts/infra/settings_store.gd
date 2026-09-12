## doc: 23 §1/§3
## 设置存取（infra，静态工具）：user://settings.json，独立于存档槽、不参与迁移链。
## 默认值唯一真源；缺文件/坏 JSON 回落默认。原子写与 Save 同口径（tmp+rename）。
class_name SettingsStore
extends RefCounted

const PATH: String = "user://settings.json"
const BUS_KEYS: Array[String] = ["bgm", "amb", "sfx_battle", "sfx_work", "ui"]
const PARTICLE_MODES: Array[String] = ["auto", "high", "low"]
const TEXT_SCALES: Array[float] = [1.0, 1.15, 1.3]


static func defaults() -> Dictionary:
	var volumes := {}
	for bus_key in BUS_KEYS:
		volumes[bus_key] = 1.0
	return {
		"master_mute": false,
		"reduce_motion": false,
		"particle_quality": "auto",
		"text_scale": 1.0,
		"volumes": volumes,
	}


## 读取并深合并默认值：坏文件/缺键一律回落默认，不抛错
static func load_settings() -> Dictionary:
	var merged := defaults()
	if not FileAccess.file_exists(PATH):
		return merged
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed == null or not (parsed is Dictionary):
		push_warning("SettingsStore: 设置文件损坏，回落默认（%s）" % PATH)
		return merged
	var data: Dictionary = parsed
	for key in ["master_mute", "reduce_motion"]:
		if data.has(key):
			merged[key] = bool(data[key])
	if data.has("particle_quality") and PARTICLE_MODES.has(String(data.particle_quality)):
		merged["particle_quality"] = String(data.particle_quality)
	if data.has("text_scale") and TEXT_SCALES.has(float(data.text_scale)):
		merged["text_scale"] = float(data.text_scale)
	if data.has("volumes") and data.volumes is Dictionary:
		for bus_key in BUS_KEYS:
			var v = data.volumes.get(bus_key)
			if v != null and float(v) >= 0.0 and float(v) <= 1.0:
				merged.volumes[bus_key] = float(v)
	return merged


## 保存前钳制越界值（load 的对称校验——防写入可保存但不可读回的脏数据）
static func save_settings(settings: Dictionary) -> bool:
	if not PARTICLE_MODES.has(String(settings.get("particle_quality", "auto"))):
		settings["particle_quality"] = "auto"
	var ts := float(settings.get("text_scale", 1.0))
	if not TEXT_SCALES.has(ts):
		settings["text_scale"] = 1.0
	if settings.has("volumes") and settings.volumes is Dictionary:
		for bus_key in BUS_KEYS:
			var v: Variant = settings.volumes.get(bus_key)
			if v == null or float(v) < 0.0 or float(v) > 1.0:
				settings.volumes[bus_key] = clampf(float(v) if v != null else 1.0, 0.0, 1.0)
	var text := JSON.stringify(settings)
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SettingsStore: 写入失败（%s）" % tmp)
		return false
	f.store_string(text)
	f.flush()
	f.close()
	var verify := FileAccess.open(tmp, FileAccess.READ)
	if verify == null or verify.get_as_text() != text:
		return false
	verify.close()
	return DirAccess.rename_absolute(tmp, PATH) == OK
