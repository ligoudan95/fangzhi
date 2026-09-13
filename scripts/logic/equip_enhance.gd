## doc: 08 §7.1（强化）/ §7（套装）
## 装备强化与套装效果（GDScript）——纯函数。
## 强化：+1~+15，消耗金属锭+灵晶，成功率递减（+10 以上有失败风险）。
## 套装：EquipSet 表效果查询与激活判定。
class_name EquipEnhance
extends RefCounted


## 强化消耗（docs/08 §7.1）：金属锭 ×n + 灵晶 ×500 × 1.3^n
static func enhance_cost(current_level: int) -> Dictionary:
	return {
		"metalIngot": current_level + 1,
		"spiritCrystal": int(round(500.0 * pow(1.3, float(current_level)))),
	}


## 强化成功率：+1~+3=100%，+4~+7=95%，+8~+10=85%，+11~+13=70%，+14~+15=50%
static func enhance_success_rate(current_level: int) -> float:
	if current_level < 3:
		return 1.0
	if current_level < 7:
		return 0.95
	if current_level < 10:
		return 0.85
	if current_level < 13:
		return 0.70
	return 0.50


## 强化上限（docs/08 §7.1）：锻造炉等级 × 3
static func max_enhance_level(forge_level: int) -> int:
	return mini(15, forge_level * 3)


## 套装激活判定：同 setId 的已装备件数 ≥ 2/3 返回效果
static func active_set_bonus(equipped_set_ids: Array) -> Dictionary:
	var counts := {}
	for sid in equipped_set_ids:
		counts[sid] = int(counts.get(sid, 0)) + 1
	var active := {}
	for sid in counts:
		if int(counts[sid]) >= 2:
			active[sid] = {"pieces": int(counts[sid]), "tier": 2}
		if int(counts[sid]) >= 3:
			active[sid]["tier"] = 3
	return active


## 强化属性倍率（docs/08 §7.1 简化）：每级 +5% 基础属性
static func enhance_multiplier(enhance_level: int) -> float:
	return 1.0 + float(enhance_level) * 0.05
