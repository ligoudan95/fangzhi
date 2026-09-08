/** V-401 战力锚点验收（02文档 §8.2）：物理输出模板 资质1000 无偏移 无装备 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeStats, powerOf, breakMult, type G } from '../src/battle/stats.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const g = JSON.parse(readFileSync(join(ROOT, 'out/config/GlobalConst.json'), 'utf8')) as G;

test('突破倍率分段正确（02 §3.3）', () => {
  assert.equal(breakMult(1, g), 1.0);
  assert.equal(breakMult(15, g), g.BRK_M2);
  assert.equal(breakMult(40, g), g.BRK_M3);
  assert.equal(breakMult(80, g), g.BRK_M4);
  assert.equal(breakMult(120, g), g.BRK_M5);
});

test('等级-战力锚点 ±15%（V-401）', () => {
  const apt = { atk: 1000, def: 1000, hp: 1000, spd: 1000, mag: 1000 };
  const off = { hp: 0, atk: 0, def: 0, spd: 0, mag: 0, res: 0 };
  const anchors: Array<[number, number, number]> = [
    [15, 1, g.ANCHOR_POW_15], [40, 2, g.ANCHOR_POW_40], [80, 4, g.ANCHOR_POW_80], [120, 8, g.ANCHOR_POW_120],
  ];
  for (const [lv, rb, anchor] of anchors) {
    const p = powerOf(computeStats(1, off, lv, apt, rb, g), g);
    const dev = Math.abs(p - anchor) / anchor;
    assert.ok(dev <= g.ANCHOR_TOL, `等级${lv} 战力${p} 偏离锚点${anchor}达${(dev * 100).toFixed(1)}%`);
  }
});
