## doc: 04 §2/§3（资质 roll/性格/突破链）/ 15 §3.2（存档只存种子）
## 灵宠个体化（GDScript 镜像）——与 TS 基准 src/logic/petIndividuality.ts 逐行对齐。
## 纯函数：捕捉时资质五维独立 roll（存种子不存值）、性格随机选一、突破消耗判定与倍率。
## 资质/性格 roll 使用独立 aptitude/nature 流（docs/15 §3.2 五流之一），不消耗战斗流。
class_name PetIndividuality
extends RefCounted


## 五维资质 roll：每维独立，在 [min,max] 闭区间均匀分布；存种子供重放（不存值）
static func roll_aptitudes(pet_row: Dictionary, seed: int) -> Dictionary:
	var rng := BattleRng.new(seed)
	# [atkMin,atkMax,defMin,defMax,hpMin,hpMax,spdMin,spdMax,magMin,magMax]
	var ranges: Array = pet_row.aptitudes
	var vals := {}
	vals["atk"] = _roll_range(rng, int(ranges[0]), int(ranges[1]))
	vals["def"] = _roll_range(rng, int(ranges[2]), int(ranges[3]))
	vals["hp"] = _roll_range(rng, int(ranges[4]), int(ranges[5]))
	vals["spd"] = _roll_range(rng, int(ranges[6]), int(ranges[7]))
	vals["mag"] = _roll_range(rng, int(ranges[8]), int(ranges[9]))
	return vals


static func _roll_range(rng: BattleRng, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(floorf(rng.next() * float(hi - lo + 1)))


## 性格 roll：从 PetBase.natures 池随机选一；存种子（JSON 导入后已是 Array，无需 split）
static func roll_nature(pet_row: Dictionary, seed: int) -> String:
	var pool: Array = _as_array(pet_row.natures)
	if pool.is_empty():
		return ""
	var rng := BattleRng.new(seed)
	return String(pool[int(floorf(rng.next() * float(pool.size())))])


## 兼容 String/Array 输入：JSON 导入后 array<string> 字段已是 Array
static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	if typeof(value) == TYPE_STRING:
		return String(value).split(";")
	return []


## 性格修正表（docs/04 §3）：返回 {stat: 修正比例}；无性格返回空
static func nature_modifiers(nature: String) -> Dictionary:
	match nature:
		"沉稳":
			return {"def": 0.05, "spd": -0.03}
		"强壮":
			return {"hp": 0.08, "spd": -0.05}
		"温顺":
			return {"hp": 0.03, "atk": -0.02}
		"坚韧":
			return {"def": 0.06, "mag": -0.03}
		"聪慧":
			return {"mag": 0.08, "hp": -0.04}
		"敏捷":
			return {"spd": 0.10, "def": -0.04}
		"凶猛":
			return {"atk": 0.08, "def": -0.05}
		"忠诚":
			return {"hp": 0.04, "atk": 0.03}
		_:
			return {}


## 突破判定（docs/04 §4 / docs/02 §3.3）：当前突破数→下一阶消耗与等级门槛
static func breakthrough_cost(
	pet_row: Dictionary, current_breaks: int, g: Dictionary
) -> Dictionary:
	if current_breaks >= 4:
		return {"can": false, "reason": "已达最高阶段"}
	var next_level := _break_level(current_breaks + 1, g)
	return {
		"can": true,
		"breakIndex": current_breaks + 1,
		"stageName": _stage_name(pet_row, current_breaks + 1),
		"requiredLevel": next_level,
		"xiuCost": _xiu_cost(current_breaks, g),
	}


static func _break_level(index: int, g: Dictionary) -> int:
	match index:
		1:
			return int(g.BRK_LV2)
		2:
			return int(g.BRK_LV3)
		3:
			return int(g.BRK_LV4)
		4:
			return int(g.BRK_LV5)
		_:
			return 999999


static func _xiu_cost(index: int, _g: Dictionary) -> int:
	# docs/02 §3.3：突破修为消耗 = 基础 500 × 1.6^index
	return int(round(500.0 * pow(1.6, float(index))))


static func _stage_name(pet_row: Dictionary, index: int) -> String:
	var chain: Array = _as_array(pet_row.breaks)
	if index < chain.size():
		return String(chain[index])
	return ""
