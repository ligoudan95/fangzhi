/**
 * 灵宠成长（TS 基准）——与 scripts/logic/pet_growth.gd 逐位一致
 * （docs/01 §144 修为驱动养成 / docs/02 §3.3 突破门槛 / docs/04 §4 突破链）。
 * 喂养数值为临时口径（GlobalConst 标注待校准）。
 */
import { breakthroughCost } from './petIndividuality.ts';

export const FEED_BASE_FALLBACK = 50;
export const FEED_STEP_FALLBACK = 10;

export type G = Record<string, number>;
export interface PetState { level: number; realmBreaks: number }
/** 与 petIndividuality.PetRow 同形（保持私有接口的本地别名） */
export interface PetRowLike {
  aptitudes: number[];
  natures: string | string[];
  breaks: string | string[];
}

/** 喂养消耗：PET_FEED_XIU_BASE + PET_FEED_XIU_STEP × (level-1) */
export function feedCost(level: number, g: G): number {
  const base = g.PET_FEED_XIU_BASE ?? FEED_BASE_FALLBACK;
  const step = g.PET_FEED_XIU_STEP ?? FEED_STEP_FALLBACK;
  return base + step * Math.max(0, level - 1);
}

/** 等级帽：当前突破数下最高等级 = 下一突破门槛（0 突破→BRK_LV2；已 4 突破→BRK_LV5 封顶） */
export function levelCap(realmBreaks: number, g: G): number {
  switch (Math.min(Math.max(realmBreaks, 0), 4)) {
    case 0: return g.BRK_LV2;
    case 1: return g.BRK_LV3;
    case 2: return g.BRK_LV4;
    default: return g.BRK_LV5;
  }
}

/** 喂养 1 级：返回 {ok, reason, cost, level}；不修改输入 */
export function feed(pet: PetState, cultivation: number, g: G): {
  ok: boolean; reason: string; cost: number; level: number;
} {
  const level = pet.level ?? 1;
  if (level >= levelCap(pet.realmBreaks ?? 0, g)) {
    return { ok: false, reason: '等级已达当前阶段上限，需突破', cost: 0, level };
  }
  const cost = feedCost(level, g);
  if (cultivation < cost) {
    return { ok: false, reason: `修为不足（需 ${cost}）`, cost, level };
  }
  return { ok: true, reason: '', cost, level: level + 1 };
}

/** 突破：等级须达门槛且消耗修为；返回 {ok, reason, cost, realmBreaks} */
export function breakthrough(
  pet: PetState, petRow: PetRowLike, cultivation: number, g: G,
): { ok: boolean; reason: string; cost: number; realmBreaks: number } {
  const breaks = pet.realmBreaks ?? 0;
  const bc = breakthroughCost(petRow, breaks, g);
  if (!bc.can) return { ok: false, reason: bc.reason, cost: 0, realmBreaks: breaks };
  if ((pet.level ?? 1) < bc.requiredLevel) {
    return { ok: false, reason: `等级不足（需 ${bc.requiredLevel}）`, cost: 0, realmBreaks: breaks };
  }
  if (cultivation < bc.xiuCost) {
    return { ok: false, reason: `修为不足（需 ${bc.xiuCost}）`, cost: bc.xiuCost, realmBreaks: breaks };
  }
  return { ok: true, reason: '', cost: bc.xiuCost, realmBreaks: breaks + 1 };
}
