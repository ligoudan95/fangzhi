/**
 * 兽潮补结算（TS 基准）——与 scripts/logic/beast_tide.gd 同口径（docs/26 §4.5）。
 * 波次枚举 + 确定性种子 + Battle 逐波结算。
 */
import { Battle, type BattleConfig, type PetInput } from '../battle/engine.ts';
import { groupInputs } from '../config/load.ts';

export function waveBoundaries(cursor: number, now: number, tzOffsetSec: number, maxWaves: number): number[] {
  const out: number[] = [];
  if (now <= cursor || maxWaves <= 0) return out;
  const localDay0 = cursor + tzOffsetSec - ((cursor + tzOffsetSec) % 86400);
  let day = localDay0;
  while (day < now + 86400 && out.length < maxWaves) {
    for (const hour of [43200, 72000]) {
      const waveUtc = day + hour - tzOffsetSec;
      if (waveUtc > cursor && waveUtc <= now) {
        out.push(waveUtc);
        if (out.length >= maxWaves) break;
      }
    }
    day += 86400;
  }
  out.sort((a, b) => a - b);
  return out;
}

/** 与 GD EquipDropRng.mix 同算法（MurmurHash3 终局） */
function mix(x: number): number {
  const u32 = (v: number): number => v >>> 0;
  const mul32 = (a: number, b: number): number => u32(Math.imul(a, b));
  let y = u32(x);
  y = mul32(y ^ (y >>> 16), 0x85EBCA6B);
  y = mul32(y ^ (y >>> 13), 0xC2B2AE35);
  return u32(y ^ (y >>> 16));
}

export function waveSeed(rootSeed: number, waveUtc: number): number {
  return mix((rootSeed & 0xFFFFFFFF) ^ (waveUtc & 0xFFFFFFFF));
}

export interface TideWaveResult { waveUtcSec: number; outcome: string; rounds: number }
export interface TideReport { waves: TideWaveResult[]; nextCursor: number; settledCount: number }

export function settleMissed(
  cursor: number, now: number, tzOffsetSec: number, rootSeed: number,
  team: PetInput[], rawTables: Record<string, unknown>, cfg: BattleConfig, g: Record<string, number>,
): TideReport {
  const maxWaves = g.TIDE_MAX_MISSED_WAVES ?? 4;
  const waves = waveBoundaries(cursor, now, tzOffsetSec, maxWaves);
  const report: TideWaveResult[] = [];
  for (const waveUtc of waves) {
    const seed = waveSeed(rootSeed, waveUtc);
    const battle = new Battle(cfg, team, groupInputs(cfg, 2), seed);
    const r = battle.run();
    report.push({ waveUtcSec: waveUtc, outcome: r.outcome, rounds: r.rounds });
  }
  return { waves: report, nextCursor: Math.max(cursor, now), settledCount: report.length };
}
