/** 配置加载：out/config/*.json → BattleConfig（07文档 §3 ConfigService 的 headless 版） */
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { BattleConfig } from '../battle/engine.ts';
import type { PetInput, PetRow, SkillRow, BuffRow } from '../battle/types.ts';
import type { G } from '../battle/stats.ts';

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
  const pool = new Map<number, number[]>();
  for (const r of readJson<{ petId: number; slot: number; skillId: number }[]>('PetSkillPool')) {
    const arr = pool.get(r.petId) ?? [];
    arr[r.slot] = r.skillId;
    pool.set(r.petId, arr);
  }
  return { g, pets, skills, buffs, skillPool: pool };
}

/** 从种族表构造战斗单位输入（资质统一值；资质roll功能后续版本接入） */
export function makePetInput(cfg: BattleConfig, petId: number, level: number, apt: number, realmBreaks: number, opts?: { captureable?: boolean; strategy?: string }): PetInput {
  const apts = { atk: apt, def: apt, hp: apt, spd: apt, mag: apt };
  return { petId, level, apts, realmBreaks, skillIds: cfg.skillPool.get(petId) ?? [], captureable: opts?.captureable, strategy: opts?.strategy };
}

/** 读取敌人组（EnemyGroup 表） */
export function groupInputs(cfg: BattleConfig, groupId: number): PetInput[] {
  const rows = readJson<{ groupId: number; slot: number; petId: number; level: number; apt: number; strategy: string }[]>('EnemyGroup')
    .filter(r => r.groupId === groupId)
    .sort((a, b) => a.slot - b.slot);
  return rows.map(r => makePetInput(cfg, r.petId, r.level, r.apt, 0, { captureable: true, strategy: r.strategy }));
}
