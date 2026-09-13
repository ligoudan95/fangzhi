## doc: 10 §12（性能验收——桌面替代探针）
## 战斗演出满负载帧率探针：窗口模式跑 battle.tscn，重复整场演出（含 Tween/伤害数字/震屏），
## 分档统计帧耗时（avg/p95/max）与内存。预算口径：中端 ≥55fps（桌面为上界参考，真机为准）。
## 运行：godot --path . -s res://tools/dev/perf_probe.gd
extends SceneTree

const WARMUP_FRAMES := 120
const MEASURE_FRAMES := 600
const BATTLE_ROUNDS := 6

var _frames := 0
var _scene: Control
var _samples: PackedFloat32Array = PackedFloat32Array()
var _rounds_done := 0
var _phase := "warmup"


func _initialize() -> void:
	_scene = preload("res://scenes/battle.tscn").instantiate()
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_frames += 1
	if _phase == "warmup":
		if _frames >= WARMUP_FRAMES:
			_phase = "measure"
			_samples.clear()
		return false
	_samples.append(delta)
	if _scene._playback != null and _scene._playback.is_done():
		if _rounds_done < BATTLE_ROUNDS:
			_scene._on_new_battle_pressed()
			_rounds_done += 1
		elif _samples.size() >= MEASURE_FRAMES:
			_report()
			quit(0)
	return false


func _report() -> void:
	var arr: Array = []
	for v in _samples:
		arr.append(float(v))
	arr.sort()
	var total := 0.0
	for v in arr:
		total += v
	var avg_ms := total / float(arr.size()) * 1000.0
	var p95_ms: float = arr[int(float(arr.size()) * 0.95)] * 1000.0
	var max_ms: float = arr[arr.size() - 1] * 1000.0
	var fps := 1000.0 / avg_ms
	var verdict := (
		"PASS(≥55fps 档)" if fps >= 55.0 else ("PASS(≥30fps 低档)" if fps >= 30.0 else "FAIL")
	)
	print(
		(
			"PERF-PROBE: frames=%d rounds=%d avg=%.2fms p95=%.2fms max=%.2fms fps=%.1f verdict=%s"
			% [arr.size(), _rounds_done, avg_ms, p95_ms, max_ms, fps, verdict]
		)
	)
	print(
		(
			"PERF-MEM: static=%.1fMB objects=%d"
			% [
				float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
				int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			]
		)
	)
