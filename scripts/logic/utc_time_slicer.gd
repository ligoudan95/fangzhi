## doc: 15 §1 / 14 §5
## UTC 时间切片（纯逻辑）——与 TS 基准 src/logic/timeSlicer.ts 逐行镜像。
## 内部只用 UTC Unix 整秒；tick=300s；四季每季 432000s（5 天），纪元前钳制为第 0 季。
class_name UtcTimeSlicer
extends RefCounted

const TICK_SEC: int = 300
const SEASON_SEC: int = 432000


## 季节序号（自纪元起累计；纪元前一律 0）
static func season_index(utc_sec: int, epoch_sec: int) -> int:
	var rel := utc_sec - epoch_sec
	if rel < 0:
		return 0
	return floori(float(rel) / float(SEASON_SEC))


## 四季循环位（0春 1夏 2秋 3冬）
static func season_of_year(utc_sec: int, epoch_sec: int) -> int:
	return season_index(utc_sec, epoch_sec) % 4


## 第一个严格大于 utc_sec 的 tick 边界
static func next_tick_boundary(utc_sec: int, epoch_sec: int) -> int:
	var rel := utc_sec - epoch_sec
	var k := floori(float(rel) / float(TICK_SEC)) + 1
	return epoch_sec + k * TICK_SEC


## 下一个季边界（纪元前 → 纪元本身）
static func next_season_boundary(utc_sec: int, epoch_sec: int) -> int:
	var rel := utc_sec - epoch_sec
	if rel < 0:
		return epoch_sec
	var k := floori(float(rel) / float(SEASON_SEC)) + 1
	return epoch_sec + k * SEASON_SEC


## 切片 [start,end)：边界 = min(下一tick, 下一季界, end)；每片带起点季节位；end<=start 返回 []
## 切片数安全上限 10000（防极大时间跨度 OOM，docs/15 §2.1 离线上限 12h≈144 切片）
static func slice_range(start_utc: int, end_utc: int, epoch_sec: int) -> Array:
	var slices: Array = []
	if end_utc <= start_utc:
		return slices
	var cursor := start_utc
	while cursor < end_utc and slices.size() < 10000:
		var boundary: int = mini(
			mini(next_tick_boundary(cursor, epoch_sec), next_season_boundary(cursor, epoch_sec)),
			end_utc
		)
		slices.append(
			{"start": cursor, "end": boundary, "season": season_of_year(cursor, epoch_sec)}
		)
		cursor = boundary
	return slices
