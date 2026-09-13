/** 配置加载：out/config/*.json → BattleConfig（07文档 §3 ConfigService 的 headless 版） */
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { BattleConfig, SkillPoolEntry } from '../battle/engine.ts';
import type { PetInput, PetRow, SkillRow, BuffRow } from '../battle/types.ts';
import type { G } from '../battle/stats.ts';
import type { AffixRow, EquipBaseRow, EquipDropConfig, EquipQualityRow, DropRuleRow } from '../equipment/drop.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

const readJson = <T>(name: string): T =>
  JSON.parse(readFileSync(join(ROOT, 'out', 'config', `${name}.json`), 'utf8')) as T;

export function loadConfig(): BattleConfig {
  const g = readJson<G>('GlobalConst');
  const pets = new Map<number, PetRow>();
  for (const p of readJson<PetRow[]>('PetBase')) pets.set(p.petId, p);
  const skills = new Map<number, SkillRow>();
  for (const s of readJson<SkillRow[]>('SkillConfig')) skills.set(s.skillId, s);
  const buffs = new Map<number, BuffRow>();
  for (const b of readJson<BuffRow[]>('BuffConfig')) buffs.set(b.buffId, b);
  const pool = new Map<number, SkillPoolEntry[]>();
  for (const r of readJson<{ petId: number; slot: number; skillId: number; learnLv: number }[]>('PetSkillPool')) {
    const arr = pool.get(r.petId) ?? [];
    arr[r.slot] = { skillId: r.skillId, learnLv: r.learnLv };
    pool.set(r.petId, arr);
  }
  return { g, pets, skills, buffs, skillPool: pool };
}

/**
 * 从种族表构造战斗单位输入；opts.apts 可传五维资质、opts.natureMods 性格修正
 * （并入引擎偏移项，docs/04 §3）——缺省保持旧行为（对拍兼容）
 */
export function makePetInput(cfg: BattleConfig, petId: number, level: number, apt: number, realmBreaks: number, opts?: {
  captureable?: boolean; strategy?: string; apts?: { atk: number; def: number; hp: number; spd: number; mag: number };
  natureMods?: Record<string, number>; statMods?: Record<string, number>;
}): PetInput {
  const apts = opts?.apts ?? { atk: apt, def: apt, hp: apt, spd: apt, mag: apt };
  const skillIds = (cfg.skillPool.get(petId) ?? [])
    .filter(entry => entry && entry.learnLv <= level)
    .map(entry => entry.skillId);
  return {
    petId, level, apts, realmBreaks, skillIds,
    captureable: opts?.captureable, strategy: opts?.strategy,
    natureMods: opts?.natureMods, statMods: opts?.statMods,
  };
}

/** 读取敌人组（EnemyGroup 表） */
export function groupInputs(cfg: BattleConfig, groupId: number): PetInput[] {
  const rows = readJson<{ groupId: number; slot: number; petId: number; level: number; apt: number; strategy: string }[]>('EnemyGroup')
    .filter(r => r.groupId === groupId)
    .sort((a, b) => a.slot - b.slot);
  return rows.map(r => makePetInput(cfg, r.petId, r.level, r.apt, 0, { captureable: true, strategy: r.strategy }));
}

/** 装备掉落配置（docs/08 M3）：DropRule + EquipBase/AffixPool/EquipQuality */
export function loadEquipmentConfig(): EquipDropConfig {
  const rules = new Map<number, DropRuleRow>();
  for (const r of readJson<Array<Record<string, unknown>>>('DropRule')) {
    rules.set(Number(r.dropId), {
      dropId: Number(r.dropId), source: Number(r.source),
      weights: ['wWhite', 'wGreen', 'wBlue', 'wPurple', 'wOrange', 'wRed'].map(k => Number(r[k])),
      luckApply: Boolean(r.luckApply), pityQuality: Number(r.pityQuality), pityCount: Number(r.pityCount),
      pityUnit: String(r.pityUnit), equipLvMode: String(r.equipLvMode),
      equipLvOffsetMin: Number(r.equipLvOffsetMin), equipLvOffsetMax: Number(r.equipLvOffsetMax),
    });
  }
  const equipBase = readJson<EquipBaseRow[]>('EquipBase');
  const affixes = readJson<AffixRow[]>('AffixPool');
  const qualities = new Map<number, EquipQualityRow>();
  for (const q of readJson<EquipQualityRow[]>('EquipQuality')) qualities.set(q.qualityId, q);
  return { rules, equipBase, affixes, qualities };
}
