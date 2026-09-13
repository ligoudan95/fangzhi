/** 玩家境界测试——与 tests/realm_progress_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { layerCost, tryAdvance, realmOfName, canUnlock, realmDisplay } from '../src/logic/realmProgress.ts';

const g = { REALM_BASE_XIU: 500, REALM_BASE_GROWTH: 2.6, REALM_LAYER_GROWTH: 1.35, REALM_LAYERS: 9 };

test('层修为：Base(n)×1.35^(k-1)', () => {
  assert.equal(layerCost(1, 1, g), 500);
  assert.equal(layerCost(1, 2, g), 675);
  assert.equal(layerCost(2, 1, g), 1300);
});

test('推进：不足/推进/满九进境/封顶', () => {
  assert.equal(tryAdvance(499, 1, 1, g).ok, false);
  assert.equal(tryAdvance(499, 1, 1, g).cost, 500);
  const r2 = tryAdvance(600, 1, 1, g);
  assert.equal(r2.ok, true);
  assert.equal(r2.cost, 500);
  assert.equal(r2.realmLayer, 2);
  const r3 = tryAdvance(999999, 1, 9, g);
  assert.equal(r3.realmId, 2);
  assert.equal(r3.realmLayer, 1);
  const r4 = tryAdvance(999999999, 10, 9, g);
  assert.equal(r4.ok, false);
  assert.equal(r4.reason, '已达十境之巅');
});

test('unlockRealm 门禁', () => {
  assert.equal(realmOfName('淬体'), 1);
  assert.equal(realmOfName('凝血'), 2);
  assert.equal(realmOfName('通脉'), 3);
  assert.equal(canUnlock('淬体', 1), true);
  assert.equal(canUnlock('凝血', 1), false);
  assert.equal(canUnlock('凝血', 2), true);
  assert.equal(canUnlock('不存在的境', 1), true);
});

test('显示名', () => {
  assert.equal(realmDisplay(1, 1, g), '淬体一重');
  assert.equal(realmDisplay(1, 3, g), '淬体三重');
  assert.equal(realmDisplay(1, 9, g), '淬体九重');
  assert.equal(realmDisplay(2, 1, g), '凝血一重');
});
