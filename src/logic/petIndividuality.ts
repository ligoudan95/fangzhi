/**
 * 灵宠个体化（TS 基准）——与 scripts/logic/pet_individuality.gd 逐行镜像。
 * docs/04 §2/§3：资质 roll、性格 roll、突破消耗。
 * 资质/性格 roll 使用独立流（docs/15 §3.2），不消耗战斗流。
 */
import { makeRng } from '../battle/engine.ts';

export interface Aptitudes { atk: number; def: number; hp: number; spd: number; mag: number }

interface PetRow { aptitudes: number[]; natures: string; breaks: string }

export function rollAptitudes(petRow: PetRow, seed: number): Aptitudes {
  const rng = makeRng(seed);
  const r = petRow.aptitudes;
  return {
    atk: _rollRange(rng, r[0], r[1]),
    def: _rollRange(rng, r[2], r[3]),
    hp: _rollRange(rng, r[4], r[5]),
    spd: _rollRange(rng, r[6], r[7]),
    mag: _rollRange(rng, r[8], r[9]),
  };
}

function _rollRange(rng: () => number, lo: number, hi: number): number {
  if (hi <= lo) return lo;
  return lo + Math.floor(rng() * (hi - lo + 1));
}

export function rollNature(petRow: PetRow, seed: number): string {
  const pool = Array.isArray(petRow.natures) ? petRow.natures : petRow.natures.split(";");
  if (pool.length === 0) return '';
  const rng = makeRng(seed);
  return pool[Math.floor(rng() * pool.length)];
}

export function natureModifiers(nature: string): Record<string, number> {
  switch (nature) {
    case '沉稳': return { def: 0.05, spd: -0.03 };
    case '强壮': return { hp: 0.08, spd: -0.05 };
    case '温顺': return { hp: 0.03, atk: -0.02 };
    case '坚韧': return { def: 0.06, mag: -0.03 };
    case '聪慧': return { mag: 0.08, hp: -0.04 };
    case '敏捷': return { spd: 0.10, def: -0.04 };
    case '凶猛': return { atk: 0.08, def: -0.05 };
    case '忠诚': return { hp: 0.04, atk: 0.03 };
    default: return {};
  }
}

interface G { BRK_LV2: number; BRK_LV3: number; BRK_LV4: number; BRK_LV5: number }

export interface BreakthroughCost {
  can: boolean; reason?: string; breakIndex?: number; stageName?: string;
  requiredLevel?: number; xiuCost?: number;
}

export function breakthroughCost(petRow: PetRow, currentBreaks: number, g: G): BreakthroughCost {
  if (currentBreaks >= 4) return { can: false, reason: '已达最高阶段' };
  const levels = [0, g.BRK_LV2, g.BRK_LV3, g.BRK_LV4, g.BRK_LV5];
  const chain = Array.isArray(petRow.breaks) ? petRow.breaks : petRow.breaks.split(';');
  return {
    can: true,
    breakIndex: currentBreaks + 1,
    stageName: chain[currentBreaks + 1] ?? '',
    requiredLevel: levels[currentBreaks + 1],
    xiuCost: Math.round(500 * Math.pow(1.6, currentBreaks)),
  };
}
