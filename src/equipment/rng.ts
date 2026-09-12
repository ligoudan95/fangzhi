/**
 * 装备掉落独立 RNG（docs/08 M3 / docs/14 R-P1-02）
 * - 与战斗 RNG 完全隔离：种子由 (rootSeed, settlementSeq, dropId, itemIndex, tag) 派生
 * - TS/GD 对拍红线：u32 语义（>>>0 / Math.imul）与 scripts/logic/equip_drop_rng.gd 逐位一致
 */

/** 流标签：算法契约常量，不得按调用点临时分配 */
export const TAG_QUALITY = 1;
export const TAG_TEMPLATE = 2;
export const TAG_LEVEL = 3;
export const TAG_AFFIX_COUNT = 4;
export const TAG_AFFIX_SELECT = 5;
export const TAG_AFFIX_VALUE = 6;
export const TAG_PITY_INDEX = 7;

const u32 = (x: number): number => x >>> 0;
const mul32 = (a: number, b: number): number => u32(Math.imul(a, b));

/** xorshift-乘法 avalanche（MurmurHash3 终局） */
export function mix(x: number): number {
  x = u32(x);
  x = mul32(x ^ (x >>> 16), 0x85EBCA6B);
  x = mul32(x ^ (x >>> 13), 0xC2B2AE35);
  return u32(x ^ (x >>> 16));
}

/** 结算域种子：一次掉落结算内共享 */
export function deriveSettlementSeed(rootSeed: number, settlementSeq: number, dropId: number): number {
  return mix(
    u32(rootSeed) ^ mul32(u32(settlementSeq), 0x9E3779B9) ^ mul32(u32(dropId), 0x85EBCA6B) ^ 0xD0E0A11C,
  );
}

/** 单件装备种子：持久化到 EquipInstance.rollSeed，鉴定时按同种子重展开 */
export function deriveItemSeed(settlementSeed: number, itemIndex: number): number {
  return mix(u32(settlementSeed) ^ mul32(u32(itemIndex) + 1, 0xC2B2AE35));
}

/** 单件装备的具名流种子 */
export function deriveStreamSeed(itemSeed: number, tag: number): number {
  return mix(u32(itemSeed) ^ mul32(u32(tag), 0x27D4EB2F));
}

/** mulberry32（与 src/battle/engine.ts makeRng 同算法，独立实例互不影响） */
export function makeEquipRng(seed: number): () => number {
  let a = seed >>> 0;
  return function next(): number {
    a = u32(a + 0x6D2B79F5);
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 加权抽取：单次 RNG 消耗，累计边界统一 `<`（TS/GD 必须一致） */
export function rollWeightedIndex(weights: number[], rng: () => number): number {
  const total = weights.reduce((sum, w) => sum + w, 0);
  if (!(total > 0)) throw new Error('权重总和必须 > 0');
  const r = rng() * total;
  let acc = 0;
  for (let i = 0; i < weights.length; i++) {
    acc += weights[i];
    if (r < acc) return i;
  }
  return weights.length - 1;
}
