## doc: 04 §1（图鉴）/ 08 §3（收集幸运加成）
## 图鉴收集系统（GDScript）——纯函数：收集进度、完成度、幸运加成计算。
## 收集数据来自存档 pets 数组中的 petId 集合。
class_name CodexSystem
extends RefCounted


## 已收集的 petId 集合
static func collected_ids(pets: Array) -> Array:
	var ids := {}
	for pet in pets:
		ids[int(pet.petId)] = true
	return ids.keys()


## 图鉴完成度（0.0~1.0）：已收集 / 全表
static func completion_ratio(pets: Array, all_pet_ids: Array) -> float:
	if all_pet_ids.is_empty():
		return 0.0
	var collected := collected_ids(pets)
	return float(collected.size()) / float(all_pet_ids.size())


## 收集幸运加成（docs/08 §3）：每 5% 完成度 +10 幸运值
static func luck_bonus(pets: Array, all_pet_ids: Array) -> int:
	var ratio := completion_ratio(pets, all_pet_ids)
	return int(floorf(ratio / 0.05)) * 10


## 图鉴条目：全部灵宠 + 已收集/未收集状态
static func codex_entries(pets: Array, pet_rows: Array) -> Array:
	var collected := {}
	for pet in pets:
		collected[int(pet.petId)] = true
	var entries: Array = []
	for row in pet_rows:
		(
			entries
			. append(
				{
					"petId": int(row.petId),
					"name": String(row.name),
					"element": int(row.element),
					"quality": int(row.quality),
					"captured": collected.has(int(row.petId)),
				}
			)
		)
	return entries
