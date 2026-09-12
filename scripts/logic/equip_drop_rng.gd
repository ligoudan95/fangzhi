## doc: 08 M3 / 14 R-P1-02
## 装备掉落独立 RNG——与 TS 基准 src/equipment/rng.ts 逐位一致。
## 种子由 (rootSeed, settlementSeq, dropId, itemIndex, tag) 派生，不接触战斗 RNG。
## 32 位无符号语义：所有运算后 & 0xFFFFFFFF；乘法经 BattleRng._mul32 拆分防 int64 溢出。
class_name EquipDropRng
extends RefCounted

## 流标签：算法契约常量，不得按调用点临时分配（与 TS 同值）
const TAG_QUALITY: int = 1
const TAG_TEMPLATE: int = 2
const TAG_LEVEL: int = 3
const TAG_AFFIX_COUNT: int = 4
const TAG_AFFIX_SELECT: int = 5
const TAG_AFFIX_VALUE: int = 6
const TAG_PITY_INDEX: int = 7


## xorshift-乘法 avalanche（MurmurHash3 终局，与 TS mix 一致）
static func mix(x_in: int) -> int:
	var x := x_in & 0xFFFFFFFF
	x = BattleRng._mul32((x ^ (x >> 16)) & 0xFFFFFFFF, 0x85EBCA6B)
	x = BattleRng._mul32((x ^ (x >> 13)) & 0xFFFFFFFF, 0xC2B2AE35)
	return (x ^ (x >> 16)) & 0xFFFFFFFF


## 结算域种子：一次掉落结算内共享
static func derive_settlement_seed(root_seed: int, settlement_seq: int, drop_id: int) -> int:
	return mix(
		(
			(root_seed & 0xFFFFFFFF)
			^ BattleRng._mul32(settlement_seq & 0xFFFFFFFF, 0x9E3779B9)
			^ BattleRng._mul32(drop_id & 0xFFFFFFFF, 0x85EBCA6B)
			^ 0xD0E0A11C
		)
	)


## 单件装备种子：持久化到 EquipInstance.rollSeed，鉴定时按同种子重展开
static func derive_item_seed(settlement_seed: int, item_index: int) -> int:
	return mix(
		(settlement_seed & 0xFFFFFFFF) ^ BattleRng._mul32((item_index & 0xFFFFFFFF) + 1, 0xC2B2AE35)
	)


## 单件装备的具名流种子
static func derive_stream_seed(item_seed: int, tag: int) -> int:
	return mix((item_seed & 0xFFFFFFFF) ^ BattleRng._mul32(tag & 0xFFFFFFFF, 0x27D4EB2F))


## mulberry32 流（复用 BattleRng，同算法独立实例）
static func make_stream(seed: int) -> BattleRng:
	return BattleRng.new(seed)


## 加权抽取：单次 RNG 消耗，累计边界统一 `<`（与 TS rollWeightedIndex 一致）
static func roll_weighted_index(weights: Array, rng: BattleRng) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 0.0:
		return -1
	var r := rng.next() * total
	var acc := 0.0
	for i in range(weights.size()):
		acc += float(weights[i])
		if r < acc:
			return i
	return weights.size() - 1
