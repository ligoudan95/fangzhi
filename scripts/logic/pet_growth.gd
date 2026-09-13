## doc: 01 §144（修为驱动养成，不设刷怪经验）/ 02 §3.3（突破门槛）/ 04 §4（突破链）
## 灵宠成长（GDScript）——与 TS 基准 src/logic/petGrowth.ts 逐位一致。
## 纯函数：修为喂养升级（等级帽 = 下一突破门槛，走 BRK_LV* 表键）、
## 突破消耗（docs/02 §3.3：基础 500 × 1.6^index 修为，等级须达 requiredLevel）。
## 喂养数值为临时口径（GlobalConst 标注待校准），机制以修为为唯一养成资源。
class_name PetGrowth
extends RefCounted

const FEED_BASE_FALLBACK := 50
const FEED_STEP_FALLBACK := 10


## 喂养消耗：PET_FEED_XIU_BASE + PET_FEED_XIU_STEP × (level-1)
static func feed_cost(level: int, g: Dictionary) -> int:
	var base: int = int(g.get("PET_FEED_XIU_BASE", FEED_BASE_FALLBACK))
	var step: int = int(g.get("PET_FEED_XIU_STEP", FEED_STEP_FALLBACK))
	return base + step * maxi(0, level - 1)


## 等级帽：当前突破数下最高等级 = 下一突破门槛（0 突破→BRK_LV2；已 4 突破→BRK_LV5 封顶）
static func level_cap(realm_breaks: int, g: Dictionary) -> int:
	match clampi(realm_breaks, 0, 4):
		0:
			return int(g.BRK_LV2)
		1:
			return int(g.BRK_LV3)
		2:
			return int(g.BRK_LV4)
		_:
			return int(g.BRK_LV5)


## 喂养 1 级：返回 {ok, reason, cost, level}；不修改输入
static func feed(pet: Dictionary, cultivation: int, g: Dictionary) -> Dictionary:
	var level := int(pet.get("level", 1))
	if level >= level_cap(int(pet.get("realmBreaks", 0)), g):
		return {"ok": false, "reason": "等级已达当前阶段上限，需突破", "cost": 0, "level": level}
	var cost := feed_cost(level, g)
	if cultivation < cost:
		return {"ok": false, "reason": "修为不足（需 %d）" % cost, "cost": cost, "level": level}
	return {"ok": true, "reason": "", "cost": cost, "level": level + 1}


## 突破：等级须达门槛且消耗修为（pet_individuality.breakthrough_cost 同源）；返回 {ok, reason, cost, realmBreaks}
static func breakthrough(
	pet: Dictionary, pet_row: Dictionary, cultivation: int, g: Dictionary
) -> Dictionary:
	var breaks := int(pet.get("realmBreaks", 0))
	var bc: Dictionary = PetIndividuality.breakthrough_cost(pet_row, breaks, g)
	if not bool(bc.can):
		return {"ok": false, "reason": String(bc.reason), "cost": 0, "realmBreaks": breaks}
	if int(pet.get("level", 1)) < int(bc.requiredLevel):
		return {
			"ok": false,
			"reason": "等级不足（需 %d）" % int(bc.requiredLevel),
			"cost": 0,
			"realmBreaks": breaks,
		}
	var cost := int(bc.xiuCost)
	if cultivation < cost:
		return {"ok": false, "reason": "修为不足（需 %d）" % cost, "cost": cost, "realmBreaks": breaks}
	return {"ok": true, "reason": "", "cost": cost, "realmBreaks": breaks + 1}
