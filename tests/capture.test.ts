/** 捕捉率验收（02文档 §5）：公式直算 + 蒙特卡洛分布 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeCaptureRate, makeRng, type G } from '../src/battle/engine.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const g = JSON.parse(readFileSync(join(ROOT, 'out/config/GlobalConst.json'), 'utf8')) as G;

test('公式直算：玉葫芦收玄兽（15%血+冰冻）≈33%', () => {
  const r = computeCaptureRate({
    gourdBase: g.CAP_GOURD_JADE, qualityCoef: g.CAP_Q3, hpPct: 0.15,
    hasControl: true, hasCaptureDebuff: false, lvlDiff: 0, capBonus: 0,
  }, g);
  assert.ok(Math.abs(r - 0.33) < 0.005, `期望0.33 实得${r}`);
});

test('公式直算：木葫芦收凡兽（15%血+中毒削弱）= 0.35×1.2 = 0.42', () => {
  const r = computeCaptureRate({
    gourdBase: g.CAP_GOURD_WOOD, qualityCoef: g.CAP_Q1, hpPct: 0.15,
    hasControl: false, hasCaptureDebuff: true, lvlDiff: 0, capBonus: 0,
  }, g);
  assert.ok(Math.abs(r - 0.42) < 0.005, `期望0.42 实得${r}`);
});

test('蒙特卡洛 1e5 次：成功率与公式一致（±1%）', () => {
  const rate = computeCaptureRate({
    gourdBase: g.CAP_GOURD_JADE, qualityCoef: g.CAP_Q3, hpPct: 0.15,
    hasControl: true, hasCaptureDebuff: false, lvlDiff: 0, capBonus: 0,
  }, g);
  const rng = makeRng(9527);
  const N = 100_000;
  let hit = 0;
  for (let i = 0; i < N; i++) if (rng() < rate) hit++;
  const sim = hit / N;
  assert.ok(Math.abs(sim - rate) < 0.01, `模拟${sim.toFixed(4)} vs 公式${rate.toFixed(4)}`);
});

test('等级压制：高10级封顶', () => {
  const a = computeCaptureRate({ gourdBase: 0.65, qualityCoef: 1, hpPct: 0.1, hasControl: true, hasCaptureDebuff: false, lvlDiff: 5, capBonus: 0 }, g);
  const b = computeCaptureRate({ gourdBase: 0.65, qualityCoef: 1, hpPct: 0.1, hasControl: true, hasCaptureDebuff: false, lvlDiff: 10, capBonus: 0 }, g);
  const c = computeCaptureRate({ gourdBase: 0.65, qualityCoef: 1, hpPct: 0.1, hasControl: true, hasCaptureDebuff: false, lvlDiff: 99, capBonus: 0 }, g);
  assert.ok(a > b && b === c, `5级(${a}) > 10级(${b}) = 99级(${c})`);
});
