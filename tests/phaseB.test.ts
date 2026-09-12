/** 矿场/兽潮 TS 测试——与 tests/phase_b_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { settleMines, type MineJob, type MineConfig } from '../src/logic/mineProduction.ts';
import { waveBoundaries, waveSeed, settleMissed } from '../src/logic/beastTide.ts';
import { loadConfig, groupInputs } from '../src/config/load.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cfg = loadConfig();
const minesRaw = JSON.parse(readFileSync(join(ROOT, 'out/config/Mine.json'), 'utf8')) as Array<{ mineId: number; ironRate: number; crystalRate: number; refinedRate: number; spiritRate: number }>;
const seasonsRaw = JSON.parse(readFileSync(join(ROOT, 'out/config/SeasonWeather.json'), 'utf8')) as Array<{ seasonId: number; mineMult: number }>;

const mconfig: MineConfig = {
  mines: new Map(minesRaw.map(m => [m.mineId, m])),
  seasons: new Map(seasonsRaw.map(s => [s.seasonId, { mineMult: s.mineMult }])),
  categoryOf: new Map([[201, 1], [202, 1], [203, 1]]),
  storageRules: new Map([[1, 200]]),
  g: { SEASON_EPOCH_UTC_SEC: 0, OFFLINE_CAP_BASE_SEC: 43200 },
};

test('矿场：浅层铁矿 1 小时 → 8 铁矿（春矿系数 1.0）', () => {
  const jobs: MineJob[] = [{ slotId: 1, mineId: 1, startedAtUtcSec: 0, assignedPetInstanceIds: [] }];
  const r = settleMines(jobs, 0, 3600, { beastShell: 0, spiritCrystal: 0, totemEmblem: 0 }, [], mconfig);
  const iron = r.outputs.filter(o => o.itemId === 201).reduce((a, o) => a + o.amount, 0);
  assert.equal(iron, 8);
  assert.equal(r.inventory.length, 1);
});

test('矿场：深层矿灵晶入钱包', () => {
  const jobs: MineJob[] = [{ slotId: 1, mineId: 3, startedAtUtcSec: 0, assignedPetInstanceIds: [] }];
  const r = settleMines(jobs, 0, 3600, { beastShell: 0, spiritCrystal: 10, totemEmblem: 0 }, [], mconfig);
  assert.ok(r.wallet.spiritCrystal > 10);
  const crystal = r.outputs.find(o => o.itemId === -1);
  assert.ok((crystal?.amount ?? 0) > 0);
});

test('矿场：倒流零产出；离线上限截断', () => {
  const jobs: MineJob[] = [{ slotId: 1, mineId: 1, startedAtUtcSec: 0, assignedPetInstanceIds: [] }];
  const rb = settleMines(jobs, 1000, 500, { beastShell: 0, spiritCrystal: 0, totemEmblem: 0 }, [], mconfig);
  assert.equal(rb.outputs.length, 0);
  const rc = settleMines(jobs, 0, 86400, { beastShell: 0, spiritCrystal: 0, totemEmblem: 0 }, [], mconfig);
  // 12h 上限 → 铁矿 ≤ 8×12=96
  const iron = rc.outputs.filter(o => o.itemId === 201).reduce((a, o) => a + o.amount, 0);
  assert.ok(iron <= 96);
});

test('兽潮：波次枚举 12:00/20:00 本地（UTC+8）', () => {
  const waves24 = waveBoundaries(0, 86400, 28800, 4);
  assert.deepEqual(waves24, [14400, 43200]);  // 24h 含 2 波：本地12:00=UTC4:00, 20:00=UTC12:00
  const waves48 = waveBoundaries(0, 172800, 28800, 4);
  assert.equal(waves48.length, 4);
});

test('兽潮：波次种子确定性 + 补结算报告', () => {
  assert.equal(waveSeed(42, 14400), waveSeed(42, 14400));
  assert.notEqual(waveSeed(42, 14400), waveSeed(42, 43200));
  const team = groupInputs(cfg, 2);
  const tables = {} as Record<string, unknown>;
  const g = JSON.parse(readFileSync(join(ROOT, 'out/config/GlobalConst.json'), 'utf8'));
  const r = settleMissed(0, 86400, 28800, 42, team, tables, cfg, g);
  assert.equal(r.waves.length, 2);  // 24h 窗口 2 波
  assert.equal(r.settledCount, 2);  // 24h 窗口 2 波
  for (const w of r.waves) assert.ok(['victory', 'defeat', 'timeout'].includes(w.outcome));
});
