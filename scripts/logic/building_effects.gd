## doc: 05 §2（建筑全表效果）/ 26 §4.1
## 建筑效果（GDScript）——与 TS 基准 src/logic/buildingEffects.ts 逐位一致。
## 纯函数：等级→效果值（effectBase + effectStep × 等级）；各系统按 effectKind 消费。
## 城防（kind 5）暂只提供数值，战斗消费待 docs/05 §9 数值细则（不私自定规则）。
class_name BuildingEffects
extends RefCounted

## 建筑表 ID 速记（docs/05 §2）
const HALL := 1
const BARN := 3
const FARM := 4
const MINE := 5
const FORGE := 7
const ALCHEMY := 8
const WAREHOUSE := 9
const TOTEM := 12


static func level_of(buildings: Array, building_id: int) -> int:
	for b in buildings:
		if int(b.buildingId) == building_id:
			return int(b.level)
	return 0


## 效果值 = effectBase + effectStep × 等级（CSV 为数值权威）
static func effect_value(buildings: Array, building_id: int, rows: Array) -> float:
	for row in rows:
		if int(row.buildingId) == building_id:
			return (
				float(row.effectBase)
				+ float(row.effectStep) * float(level_of(buildings, building_id))
			)
	return 0.0


## 灵田田位数（kind 1）
static func field_slots(buildings: Array, rows: Array) -> int:
	return int(effect_value(buildings, FARM, rows))


## 矿场同时开采矿层数（kind 1）
static func mine_slots(buildings: Array, rows: Array) -> int:
	return int(effect_value(buildings, MINE, rows))


## 锻造炉/药庐生产队列容量（kind 3，向下取整至少 1）
static func queue_cap(buildings: Array, station_building_id: int, rows: Array) -> int:
	return maxi(1, int(floorf(effect_value(buildings, station_building_id, rows))))


## 仓库储量上限倍率（kind 2，至少 1.0）
static func storage_cap_mult(buildings: Array, rows: Array) -> float:
	return maxf(1.0, effect_value(buildings, WAREHOUSE, rows))


## 离线收益上限秒数（图腾柱 kind 1：效果值按小时解释，钳在 [基础, 图腾上限]）
static func offline_cap_sec(buildings: Array, rows: Array, g: Dictionary) -> int:
	var base := int(g.OFFLINE_CAP_BASE_SEC)
	var hours := effect_value(buildings, TOTEM, rows)
	var cap := clampi(int(hours * 3600.0), base, int(g.OFFLINE_CAP_TOTEM_SEC))
	return cap


## 升级上限：议事堂自身用表 maxLevel；其余建筑受议事堂等级约束（docs/05 §2）
static func upgrade_cap(buildings: Array, building_id: int, rows: Array) -> int:
	var row := {}
	for r in rows:
		if int(r.buildingId) == building_id:
			row = r
			break
	if row.is_empty():
		return 0
	if building_id == HALL:
		return int(row.maxLevel)
	return mini(int(row.maxLevel), level_of(buildings, HALL))
