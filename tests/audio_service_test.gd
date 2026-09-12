## doc: 11 §7 / 13 §8
## 音频服务最小实装测试：池化、缺失资产容错（外部交付门禁）；不含听感验收。
extends GdUnitTestSuite

const AUDIO_SCRIPT: GDScript = preload("res://scripts/infra/audio_service.gd")


func test_missing_assets_fail_gracefully() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)
	assert_bool(audio.play_bgm("res://audio/missing.ogg")).is_false()
	assert_bool(audio.play_sfx("res://audio/missing.ogg")).is_false()


func test_sfx_pool_reuses_channels() -> void:
	var audio: Node = auto_free(AUDIO_SCRIPT.new())
	add_child(audio)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(2205)
	wav.data = data
	var first: AudioStreamPlayer = audio._acquire_sfx()
	first.stream = wav
	first.play()
	assert_bool(first.playing).is_true()
	var second: AudioStreamPlayer = audio._acquire_sfx()
	assert_bool(second != first).is_true()
	first.stop()
	var third: AudioStreamPlayer = audio._acquire_sfx()
	assert_bool(third == first).is_true()
