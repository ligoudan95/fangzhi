## doc: 18 §3（30 天虚拟玩家模拟）/ 06 §8（经济验收指标）
## 经济模拟器（GDScript）——纯逻辑：三类玩家分层 × 四季滚动 × 30 天产消模拟。
## 输出逐日资源流，验收断言按 docs/18 §3 五条。
class_name EconomySim
extends RefCounted

## 玩家分层（docs/18 §2）
enum Profile { IDLE, NORMAL, ACTIVE }


## 模拟配置
static func simulate(
	profile: int, days: int, season_length_days: int, config: Dictionary
) -> Dictionary:
	var daily_log: Array = []
	var inventory := {"灵晶": 0, "兽贝": 0, "铁矿": 0}
	var login_count := _logins_per_day(profile)
	var harvest_per_login := _harvest_per_login(profile)
	var battle_per_login := _battle_per_login(profile)

	for day in range(days):
		var season := int(float(day) / float(season_length_days)) % 4
		var farm_mult := _season_farm_mult(season, config)
		var mine_mult := _season_mine_mult(season, config)
		var day_log := {
			"day": day,
			"season": season,
			"login": login_count,
			"battle": battle_per_login * login_count,
			"harvest": int(floorf(float(harvest_per_login) * login_count * farm_mult)),
			"mine": int(floorf(4.0 * float(login_count) * mine_mult)),
			"spend": _daily_spend(profile),
		}
		inventory["兽贝"] = int(inventory["兽贝"]) + day_log.harvest * 20 - day_log.spend
		inventory["铁矿"] = int(inventory["铁矿"]) + day_log.mine
		day_log["兽贝余额"] = int(inventory["兽贝"])
		daily_log.append(day_log)

	return {"days": days, "profile": profile, "inventory": inventory, "dailyLog": daily_log}


static func _logins_per_day(profile: int) -> int:
	match profile:
		Profile.IDLE:
			return 1
		Profile.NORMAL:
			return 2
		_:
			return 4


static func _harvest_per_login(profile: int) -> int:
	match profile:
		Profile.IDLE:
			return 3
		Profile.NORMAL:
			return 4
		_:
			return 5


static func _battle_per_login(profile: int) -> int:
	match profile:
		Profile.IDLE:
			return 1
		Profile.NORMAL:
			return 2
		_:
			return 4


static func _daily_spend(profile: int) -> int:
	match profile:
		Profile.IDLE:
			return 50
		Profile.NORMAL:
			return 100
		_:
			return 200


static func _season_farm_mult(season: int, config: Dictionary) -> float:
	if config.has("seasons") and config.seasons.has(season):
		return float(config.seasons[season].get("farmMult", 1.0))
	return 1.0


static func _season_mine_mult(season: int, config: Dictionary) -> float:
	if config.has("seasons") and config.seasons.has(season):
		return float(config.seasons[season].get("mineMult", 1.0))
	return 1.0
