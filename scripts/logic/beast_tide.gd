## doc: 26 §4.5（兽潮错过结算）/ 05 §9 / 15 §1.5
## 兽潮补结算（GDScript）——本地 12:00/20:00 波次枚举 → 逐波确定性战斗 → 报告。
## 与 TS 基准 src/logic/beastTide.ts 同口径；战斗种子 = 波次 UTC 秒哈希派生。
class_name BeastTide
extends RefCounted


## 波次 UTC 边界：本地 12:00/20:00 → UTC 秒（tz_offset 为本地-UTC 秒差，由 View 注入）
static func wave_boundaries(cursor: int, now: int, tz_offset_sec: int, max_waves: int) -> Array:
	var out: Array = []
	if now <= cursor or max_waves <= 0:
		return out
	# 本地日 0 点对应的 UTC 秒
	var local_day0: int = cursor + tz_offset_sec - ((cursor + tz_offset_sec) % 86400)
	var day: int = local_day0
	while day < now + 86400 and out.size() < max_waves:
		for hour in [43200, 72000]:  # 本地 12:00 / 20:00
			var wave_utc: int = day + hour - tz_offset_sec
			if wave_utc > cursor and wave_utc <= now:
				out.append(wave_utc)
				if out.size() >= max_waves:
					break
		day += 86400
	out.sort()
	return out


## 波次种子：root 与波次 UTC 秒确定性派生（独立于战斗正式流）
static func wave_seed(root_seed: int, wave_utc: int) -> int:
	return EquipDropRng.mix((root_seed & 0xFFFFFFFF) ^ (wave_utc & 0xFFFFFFFF))


## 补结算：逐波 Battle（守方=玩家队）→ 胜利记 dropId=4（凶兽潮），失败记防守失败。
## 纯逻辑：输入（游标/队伍/配置），输出报告；不改输入。
static func settle_missed(
	cursor: int,
	now: int,
	tz_offset_sec: int,
	root_seed: int,
	team: Array,
	tables: Dictionary,
	cfg: Dictionary,
	g: Dictionary
) -> Dictionary:
	var max_waves := 4
	if g.has("TIDE_MAX_MISSED_WAVES"):
		max_waves = int(g.TIDE_MAX_MISSED_WAVES)
	var waves: Array = wave_boundaries(cursor, now, tz_offset_sec, max_waves)
	var report: Array = []
	for wave_utc in waves:
		var seed := wave_seed(root_seed, int(wave_utc))
		var battle := Battle.new(cfg, team, BattleSetup.group_inputs(tables, cfg, 2), seed)
		var r: Dictionary = battle.run()
		var entry := {
			"waveUtcSec": int(wave_utc), "outcome": String(r.outcome), "rounds": int(r.rounds)
		}
		report.append(entry)
	return {"waves": report, "nextCursor": maxi(cursor, now), "settledCount": report.size()}
