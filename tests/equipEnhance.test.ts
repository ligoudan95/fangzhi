/** 装备强化/套装测试——与 tests/equip_enhance_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { enhanceCost, enhanceSuccessRate, maxEnhanceLevel, activeSetBonus, enhanceMultiplier } from '../src/logic/equipEnhance.ts';

test('强化消耗：金属锭递增+灵晶指数递增', () => {
  const c0 = enhanceCost(0);
  const c5 = enhanceCost(5);
  const c10 = enhanceCost(10);
  assert.equal(c0.metalIngot, 1);
  assert.equal(c5.metalIngot, 6);
  assert.ok(c10.spiritCrystal > c5.spiritCrystal);
  assert.ok(c5.spiritCrystal > c0.spiritCrystal);
});

test('强化成功率：低级满、高级递减', () => {
  assert.equal(enhanceSuccessRate(0), 1.0);
  assert.equal(enhanceSuccessRate(2), 1.0);
  assert.ok(enhanceSuccessRate(3) < 1.0);
  assert.ok(enhanceSuccessRate(10) < enhanceSuccessRate(7));
  assert.ok(enhanceSuccessRate(14) < enhanceSuccessRate(11));
});

test('强化上限：锻造炉等级 ×3，封顶 15', () => {
  assert.equal(maxEnhanceLevel(1), 3);
  assert.equal(maxEnhanceLevel(5), 15);
  assert.equal(maxEnhanceLevel(10), 15);
});

test('套装激活：2 件触发 tier2、3 件触发 tier3', () => {
  const active = activeSetBonus([1, 1, 1, 2, 2, 3]);
  assert.equal(active.get(1)?.tier, 3);
  assert.equal(active.get(1)?.pieces, 3);
  assert.equal(active.get(2)?.tier, 2);
  assert.equal(active.has(3), false);
});

test('强化属性倍率：每级 +5%', () => {
  assert.equal(enhanceMultiplier(0), 1.0);
  assert.equal(enhanceMultiplier(5), 1.25);
  assert.equal(enhanceMultiplier(15), 1.75);
});
