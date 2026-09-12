## doc: 23 §1-§3
## 设置存取与浮层测试：默认回落、持久化往返、坏文件容错、总线音量应用。
extends GdUnitTestSuite

const SETTINGS_SCRIPT: GDScript = preload("res://scripts/infra/settings_store.gd")


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	for suffix in ["", ".tmp"]:
		var path: String = SettingsStore.PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_defaults_when_missing() -> void:
	var s := SettingsStore.load_settings()
	assert_bool(bool(s.master_mute)).is_false()
	assert_bool(bool(s.reduce_motion)).is_false()
	assert_str(String(s.particle_quality)).is_equal("auto")
	assert_float(float(s.text_scale)).is_equal(1.0)
	for bus_key in SettingsStore.BUS_KEYS:
		assert_float(float(s.volumes[bus_key])).is_equal(1.0)


func test_roundtrip_persists() -> void:
	var s := SettingsStore.load_settings()
	s.reduce_motion = true
	s.particle_quality = "low"
	s.text_scale = 1.3
	s.volumes.bgm = 0.4
	assert_bool(SettingsStore.save_settings(s)).is_true()
	var loaded := SettingsStore.load_settings()
	assert_bool(bool(loaded.reduce_motion)).is_true()
	assert_str(String(loaded.particle_quality)).is_equal("low")
	assert_float(float(loaded.text_scale)).is_equal(1.3)
	assert_float(float(loaded.volumes.bgm)).is_equal(0.4)


func test_corrupt_file_falls_back_to_defaults() -> void:
	var f := FileAccess.open(SettingsStore.PATH, FileAccess.WRITE)
	f.store_string("{不是 json")
	f.close()
	var s := SettingsStore.load_settings()
	assert_bool(bool(s.reduce_motion)).is_false()
	assert_str(String(s.particle_quality)).is_equal("auto")


func test_invalid_values_clamped_to_defaults() -> void:
	var f := FileAccess.open(SettingsStore.PATH, FileAccess.WRITE)
	var payload := (
		'{"reduce_motion": true, "particle_quality": "ultra", '
		+ '"text_scale": 9.9, "volumes": {"bgm": 5.0}}'
	)
	f.store_string(payload)
	f.close()
	var s := SettingsStore.load_settings()
	assert_bool(bool(s.reduce_motion)).is_true()
	assert_str(String(s.particle_quality)).is_equal("auto")
	assert_float(float(s.text_scale)).is_equal(1.0)
	assert_float(float(s.volumes.bgm)).is_equal(1.0)


## 浮层冒烟：构建 UI、切换即持久化、音频总线即时生效、关闭释放
func test_settings_view_smoke() -> void:
	var view: CanvasLayer = auto_free(preload("res://scripts/view/settings_view.gd").new())
	add_child(view)
	assert_int(view._sliders.size()).is_equal(SettingsStore.BUS_KEYS.size())
	view._motion_check.set_pressed_no_signal(true)
	view._on_motion_toggled(true)
	var s := SettingsStore.load_settings()
	assert_bool(bool(s.reduce_motion)).is_true()
	var bus_index := AudioServer.get_bus_index("BGM")
	view._on_volume_changed(0.5, "bgm")
	assert_float(AudioServer.get_bus_volume_db(bus_index)).is_equal_approx(linear_to_db(0.5), 0.01)
	view._on_close_pressed()
