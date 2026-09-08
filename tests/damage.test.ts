/** 伤害管线验收（02文档 §4 / 03文档 §3） */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { calcDamage, clash, type G } from '../src/battle/engine.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const g = JSON.parse(readFileSync(join(ROOT, 'out/config/GlobalConst.json'), 'utf8')) as G;
const neutral = { hit: true, crit: false, float: 1.0 };

test('克制系数：火克金 1.5 / 金克木 1.5 / 反向 0.75 / 无关 1.0', () => {
  assert.equal(clash(4, 1, g), 1.5); // 火克金
  assert.equal(clash(1, 2, g), 1.5); // 金克木
  assert.equal(clash(1, 4, g), 0.75); // 金被火克
  assert.equal(clash(4, 3, g), 0.75); // 火被水克
  assert.equal(clash(1, 3, g), 1.0);  // 金水无关
});

test('基础伤害：攻1000×倍率150%，防御=220×等级 → 减免50% → 750', () => {
  const d = calcDamage({
    atkStat: 1000, power: 1.5, isPhys: true,
    attackerElement: 1, defenderElement: 3, skillElement: 0,
    defStat: 220 * 40, defenderLevel: 40, dmgMod: 1, markPct: 0,
  }, neutral, g);
  assert.equal(d, 750);
});

test('克制与暴击：上火打金 750×1.5=1125；再暴击×1.5=1688（取整）', () => {
  const inp = {
    atkStat: 1000, power: 1.5, isPhys: true,
    attackerElement: 4, defenderElement: 1, skillElement: 0,
    defStat: 220 * 40, defenderLevel: 40, dmgMod: 1, markPct: 0,
  };
  assert.equal(calcDamage(inp, neutral, g), Math.round(1125));
  assert.equal(calcDamage(inp, { hit: true, crit: true, float: 1.0 }, g), Math.round(1687.5));
});

test('灼印标记：受火伤+30% 生效', () => {
  const base = {
    atkStat: 1000, power: 1.0, isPhys: false,
    attackerElement: 4, defenderElement: 5, skillElement: 4,
    defStat: 220 * 40, defenderLevel: 40, dmgMod: 1, markPct: 0,
  };
  const withMark = calcDamage({ ...base, markPct: 0.3 }, neutral, g);
  assert.equal(withMark, Math.round(calcDamage(base, neutral, g) * 1.3));
});

test('减免上限 70%（MIT_CAP）', () => {
  const d = calcDamage({
    atkStat: 1000, power: 1.0, isPhys: true,
    attackerElement: 1, defenderElement: 3, skillElement: 0,
    defStat: 5000 * 40, defenderLevel: 40, dmgMod: 1, markPct: 0,
  }, neutral, g);
  assert.equal(d, Math.round(1000 * (1 - 0.7))); // 被钳制在30%输出
});
