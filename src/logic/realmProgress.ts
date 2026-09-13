/**
 * 玩家境界推进（TS 基准）——与 scripts/logic/realm_progress.gd 逐位一致
 * （docs/02 §2.2 层修为公式 / docs/01 §144 修为驱动）。
 * 十境后五境为挑战驱动，本模块仅覆盖修为公式与门禁。
 */

export const REALM_NAMES = ['', '淬体', '凝血', '通脉', '开窍', '图腾', '撼山', '踏荒', '通天', '荒主', '荒神'];
export const REALM_MAX = 10;
export const LAYER_NUMBERS = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
const BASE_FALLBACK = 500.0;
const BASE_GROWTH_FALLBACK = 2.6;
const LAYER_GROWTH_FALLBACK = 1.35;
const LAYERS_FALLBACK = 9;

export type G = Record<string, number>;

/** 第 n 境第 k 层修为需求：500×2.6^(n-1) × 1.35^(k-1) */
export function layerCost(realmId: number, layer: number, g: G): number {
  const base = g.REALM_BASE_XIU ?? BASE_FALLBACK;
  const bg = g.REALM_BASE_GROWTH ?? BASE_GROWTH_FALLBACK;
  const lg = g.REALM_LAYER_GROWTH ?? LAYER_GROWTH_FALLBACK;
  return Math.round(base * Math.pow(bg, realmId - 1) * Math.pow(lg, layer - 1));
}

/** 每境层数（表驱动，默认 9） */
export function layersPerRealm(g: G): number {
  return g.REALM_LAYERS ?? LAYERS_FALLBACK;
}

/** 推进判定：层满 9 → 进境归一层；荒神 9 层封顶 */
export function tryAdvance(
  cultivation: number, realmId: number, realmLayer: number, g: G,
): { ok: boolean; reason: string; cost: number; realmId: number; realmLayer: number } {
  const layers = layersPerRealm(g);
  if (realmId >= REALM_MAX && realmLayer >= layers) {
    return { ok: false, reason: '已达十境之巅', cost: 0, realmId, realmLayer };
  }
  let nextRealm = realmId;
  let nextLayer = realmLayer + 1;
  if (nextLayer > layers) {
    nextRealm = realmId + 1;
    nextLayer = 1;
  }
  const cost = layerCost(realmId, realmLayer, g);
  if (cultivation < cost) {
    return { ok: false, reason: `修为不足（需 ${cost}）`, cost, realmId, realmLayer };
  }
  return { ok: true, reason: '', cost, realmId: nextRealm, realmLayer: nextLayer };
}

/** 境界名 → 境序号（unlockRealm 字符串映射；未知名视为无门槛） */
export function realmOfName(realmName: string): number {
  const i = REALM_NAMES.indexOf(realmName);
  return i >= 1 ? i : 1;
}

/** unlockRealm 门禁：玩家境序号 ≥ 解锁境序号 */
export function canUnlock(unlockRealm: string, playerRealmId: number): boolean {
  return playerRealmId >= realmOfName(unlockRealm);
}

/** 显示名："淬体三重"；越界钳制 */
export function realmDisplay(realmId: number, realmLayer: number, g: G): string {
  const layers = layersPerRealm(g);
  const rid = Math.min(Math.max(realmId, 1), REALM_MAX);
  const layer = Math.min(Math.max(realmLayer, 1), layers);
  const layerTxt = layer >= layers ? '九重' : `${LAYER_NUMBERS[layer]}重`;
  return REALM_NAMES[rid] + layerTxt;
}
