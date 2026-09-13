## doc: 05 §4（灵宠派遣）/ 26 §4.4（体力/心情）
## 灵宠派遣（GDScript）——纯函数：体力消耗/恢复、派遣效率、兽栏休息。
## 体力/心情使用整数定点（千分之一），避免在线分批与离线结算浮点漂移（docs/15 §3.2）。
class_name PetDispatch
extends RefCounted

## 体力常量（GlobalConst 覆盖；此处为 fallback）
const STAMINA_MAX_FALLBACK := 100
const STAMINA_DRAIN_PER_H_FALLBACK := 10
const MOOD_MAX_FALLBACK := 100
const BARN_MOOD_REGEN_PER_H_FALLBACK := 20


## 派遣体力检查：足够返回 true
static func can_dispatch(condition: Dictionary, g: Dictionary) -> bool:
	var stamina_max: int = int(g.get("STAMINA_MAX", STAMINA_MAX_FALLBACK))
	return int(condition.get("staminaMilli", stamina_max * 1000)) >= 20_000  # 至少 20 体力


## 派遣效率（docs/05 §4）：体力比例 × 心情比例 × 建筑加成
static func dispatch_efficiency(
	condition: Dictionary, building_bonus: float, g: Dictionary
) -> float:
	var stamina_max: int = int(g.get("STAMINA_MAX", STAMINA_MAX_FALLBACK))
	var mood_max: int = int(g.get("MOOD_MAX", MOOD_MAX_FALLBACK))
	var stamina_ratio := clampf(
		float(int(condition.get("staminaMilli", stamina_max * 1000))) / float(stamina_max * 1000),
		0.0,
		1.0
	)
	var mood_ratio := clampf(
		float(int(condition.get("moodMilli", mood_max * 1000))) / float(mood_max * 1000), 0.0, 1.0
	)
	# 体力占 70% 权重，心情占 30%
	return clampf(stamina_ratio * 0.7 + mood_ratio * 0.3 + building_bonus, 0.1, 2.0)


## 派遣结算：扣体力+心情，返回新状态（不修改输入）
static func settle_dispatch(condition: Dictionary, hours: float, g: Dictionary) -> Dictionary:
	var next := condition.duplicate()
	var drain_per_h: int = int(g.get("STAMINA_DRAIN_PER_H", STAMINA_DRAIN_PER_H_FALLBACK)) * 1000
	var stamina_cost := int(drain_per_h * hours)
	next["staminaMilli"] = maxi(0, int(next.get("staminaMilli", 100_000)) - stamina_cost)
	# 心情缓慢下降（派遣中每小时 -5）
	next["moodMilli"] = maxi(0, int(next.get("moodMilli", 100_000)) - int(5000 * hours))
	return next


## 兽栏休息：恢复体力+心情（docs/05 §2）
static func settle_rest(
	condition: Dictionary, hours: float, barn_level: int, g: Dictionary
) -> Dictionary:
	var next := condition.duplicate()
	var stamina_max: int = int(g.get("STAMINA_MAX", STAMINA_MAX_FALLBACK)) * 1000
	var mood_max: int = int(g.get("MOOD_MAX", MOOD_MAX_FALLBACK)) * 1000
	# 兽栏等级加成：基础恢复 15/h + 等级×1.5/h（docs/05 §2）
	var stamina_regen := int((15.0 + 1.5 * float(barn_level)) * 1000.0 * hours)
	var mood_regen: int = int(g.get("BARN_MOOD_REGEN_PER_H", BARN_MOOD_REGEN_PER_H_FALLBACK)) * 1000
	var mood_gain := int(float(mood_regen) * hours)
	next["staminaMilli"] = mini(
		stamina_max, int(next.get("staminaMilli", stamina_max)) + stamina_regen
	)
	next["moodMilli"] = mini(mood_max, int(next.get("moodMilli", mood_max)) + mood_gain)
	return next
