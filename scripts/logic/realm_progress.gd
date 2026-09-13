## doc: 02 §2.2（境界时长与修为曲线）/ 01 §144（修为驱动推进）
## 玩家境界推进（GDScript）——与 TS 基准 src/logic/realmProgress.ts 逐位一致。
## 纯函数：层修为需求（Base(n)×1.35^(k-1)）、推进判定、境界名/显示、unlockRealm 门禁。
## 十境后五境为挑战驱动（docs/02 §2.3），本模块仅覆盖修为公式与门禁；挑战接入另计。
class_name RealmProgress
extends RefCounted

## 十境（docs/02 §2.3）；索引 0 未用，realmId 从 1 起
const REALM_NAMES: Array = [
	"",
	"淬体",
	"凝血",
	"通脉",
	"开窍",
	"图腾",
	"撼山",
	"踏荒",
	"通天",
	"荒主",
	"荒神",
]
const REALM_MAX := 10
const BASE_FALLBACK := 500.0
const BASE_GROWTH_FALLBACK := 2.6
const LAYER_GROWTH_FALLBACK := 1.35
const LAYERS_FALLBACK := 9
const LAYER_NUMBERS: Array = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]


## 第 n 境第 k 层修为需求：500×2.6^(n-1) × 1.35^(k-1)
static func layer_cost(realm_id: int, layer: int, g: Dictionary) -> int:
	var base: float = float(g.get("REALM_BASE_XIU", BASE_FALLBACK))
	var bg: float = float(g.get("REALM_BASE_GROWTH", BASE_GROWTH_FALLBACK))
	var lg: float = float(g.get("REALM_LAYER_GROWTH", LAYER_GROWTH_FALLBACK))
	return int(round(base * pow(bg, float(realm_id) - 1.0) * pow(lg, float(layer) - 1.0)))


## 每境层数（表驱动，默认 9）
static func layers_per_realm(g: Dictionary) -> int:
	return int(g.get("REALM_LAYERS", LAYERS_FALLBACK))


## 推进判定：层满 9 → 进境归一层；荒神 9 层封顶；返回 {ok, reason, cost, realmId, realmLayer}
static func try_advance(
	cultivation: int, realm_id: int, realm_layer: int, g: Dictionary
) -> Dictionary:
	var layers := layers_per_realm(g)
	if realm_id >= REALM_MAX and realm_layer >= layers:
		return {
			"ok": false,
			"reason": "已达十境之巅",
			"cost": 0,
			"realmId": realm_id,
			"realmLayer": realm_layer
		}
	var next_realm := realm_id
	var next_layer := realm_layer + 1
	if next_layer > layers:
		next_realm = realm_id + 1
		next_layer = 1
	var cost := layer_cost(realm_id, realm_layer, g)
	if cultivation < cost:
		return {
			"ok": false,
			"reason": "修为不足（需 %d）" % cost,
			"cost": cost,
			"realmId": realm_id,
			"realmLayer": realm_layer
		}
	return {"ok": true, "reason": "", "cost": cost, "realmId": next_realm, "realmLayer": next_layer}


## 境界名 → 境序号（unlockRealm 字符串映射；未知名视为无门槛）
static func realm_of_name(realm_name: String) -> int:
	for i in range(1, REALM_NAMES.size()):
		if String(REALM_NAMES[i]) == realm_name:
			return i
	return 1


## unlockRealm 门禁：玩家境序号 ≥ 解锁境序号
static func can_unlock(unlock_realm: String, player_realm_id: int) -> bool:
	return player_realm_id >= realm_of_name(unlock_realm)


## 显示名："淬体三重"；越界钳制
static func realm_display(realm_id: int, realm_layer: int, g: Dictionary) -> String:
	var layers := layers_per_realm(g)
	var rid := clampi(realm_id, 1, REALM_MAX)
	var layer := clampi(realm_layer, 1, layers)
	var layer_txt := "九重" if layer >= layers else "%s重" % String(LAYER_NUMBERS[layer])
	return String(REALM_NAMES[rid]) + layer_txt
