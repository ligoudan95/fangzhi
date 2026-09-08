## doc: 02 §3 / §8.1
## 属性成长模型——最终属性 = (种族基础 + 等级×种族成长×资质/1000) × 突破倍率
## × 境界倍率^突破数 × (1+偏移)；战力 = 六维加权和。
## 与 TS 基准 src/battle/stats.ts 逐行对齐（对拍红线：同输入必同输出）。
class_name BattleStats
extends RefCounted

## 定位模板（02 §3.2）：1物理 2法术 3坦克 4辅助（数值与 TS TEMPLATES 完全一致）
const TEMPLATES: Dictionary = {
	1:
	{
		"name": "phys",
		"base": {"hp": 500, "atk": 55, "def": 33, "spd": 40, "mag": 20, "res": 20},
		"grow": {"hp": 48, "atk": 5.2, "def": 3.1, "spd": 3.0, "mag": 1.8, "res": 1.8},
	},
	2:
	{
		"name": "mage",
		"base": {"hp": 450, "atk": 20, "def": 20, "spd": 42, "mag": 55, "res": 26},
		"grow": {"hp": 42, "atk": 1.8, "def": 1.9, "spd": 3.1, "mag": 5.2, "res": 2.4},
	},
	3:
	{
		"name": "tank",
		"base": {"hp": 650, "atk": 40, "def": 45, "spd": 32, "mag": 18, "res": 30},
		"grow": {"hp": 60, "atk": 3.6, "def": 4.2, "spd": 2.4, "mag": 1.6, "res": 2.8},
	},
	4:
	{
		"name": "support",
		"base": {"hp": 520, "atk": 25, "def": 28, "spd": 44, "mag": 35, "res": 28},
		"grow": {"hp": 48, "atk": 2.2, "def": 2.6, "spd": 3.3, "mag": 3.2, "res": 2.6},
	},
}


## 突破倍率：按等级取阶段（02 §3.3）
static func break_mult(level: int, g: Dictionary) -> float:
	if level >= int(g["BRK_LV5"]):
		return float(g["BRK_M5"])
	if level >= int(g["BRK_LV4"]):
		return float(g["BRK_M4"])
	if level >= int(g["BRK_LV3"]):
		return float(g["BRK_M3"])
	if level >= int(g["BRK_LV2"]):
		return float(g["BRK_M2"])
	return 1.0


## 成长公式：apt/off 为 {atk,def,hp,spd,mag(,res)} 字典，返回六维整数 Stats。
## 对拍注意：除法必须用 /1000.0——GDScript 的 int/int 是整除，会破坏与 TS 的对拍。
## res 抗性成长随灵力资质（v0 简化：资质表仅 5 维，与 TS 同注释）。
static func compute_stats(
	tpl: int, off: Dictionary, level: int, apt: Dictionary, realm_breaks: int, g: Dictionary
) -> Dictionary:
	var t: Dictionary = TEMPLATES[tpl]
	var base: Dictionary = t["base"]
	var grow: Dictionary = t["grow"]
	var bm: float = break_mult(level, g) * pow(float(g["REALM_MULT"]), realm_breaks)
	var raw := {
		"hp": base["hp"] + level * grow["hp"] * (apt["hp"] / 1000.0),
		"atk": base["atk"] + level * grow["atk"] * (apt["atk"] / 1000.0),
		"def": base["def"] + level * grow["def"] * (apt["def"] / 1000.0),
		"spd": base["spd"] + level * grow["spd"] * (apt["spd"] / 1000.0),
		"mag": base["mag"] + level * grow["mag"] * (apt["mag"] / 1000.0),
		"res": base["res"] + level * grow["res"] * (apt["mag"] / 1000.0),
	}
	return {
		"hp": roundi(raw["hp"] * bm * (1.0 + off["hp"])),
		"atk": roundi(raw["atk"] * bm * (1.0 + off["atk"])),
		"def": roundi(raw["def"] * bm * (1.0 + off["def"])),
		"spd": roundi(raw["spd"] * bm * (1.0 + off["spd"])),
		"mag": roundi(raw["mag"] * bm * (1.0 + off["mag"])),
		"res": roundi(raw["res"] * bm * (1.0 + off["res"])),
	}


## 战力公式（02 §8.1）：六维加权和取整
static func power_of(s: Dictionary, g: Dictionary) -> int:
	return roundi(
		(
			s["hp"] * g["POWER_W_HP"]
			+ s["atk"] * g["POWER_W_ATK"]
			+ s["def"] * g["POWER_W_DEF"]
			+ s["mag"] * g["POWER_W_MAG"]
			+ s["res"] * g["POWER_W_RES"]
			+ s["spd"] * g["POWER_W_SPD"]
		)
	)
