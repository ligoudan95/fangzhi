/** 灵宠派遣测试——与 tests/pet_dispatch_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { canDispatch, dispatchEfficiency, settleDispatch, settleRest } from '../src/logic/petDispatch.ts';

test('派遣检查：体力 ≥20 可派遣', () => {
  assert.equal(canDispatch({ staminaMilli: 100_000, moodMilli: 100_000 }, {}), true);
  assert.equal(canDispatch({ staminaMilli: 15_000, moodMilli: 100_000 }, {}), false);
});

test('派遣效率：满体力+好心情 ≈1.0；低体力降低', () => {
  const full = dispatchEfficiency({ staminaMilli: 100_000, moodMilli: 100_000 }, 0, {});
  const low = dispatchEfficiency({ staminaMilli: 20_000, moodMilli: 100_000 }, 0, {});
  assert.ok(full > 0.95);
  assert.ok(low < full);
  const boosted = dispatchEfficiency({ staminaMilli: 100_000, moodMilli: 100_000 }, 0.5, {});
  assert.ok(boosted > full);
});

test('派遣结算：体力+心情扣减，不低于 0', () => {
  const r = settleDispatch({ staminaMilli: 50_000, moodMilli: 80_000 }, 2.5, {});
  assert.equal(r.staminaMilli, 25_000);  // 50k - 10k/h × 2.5h
  assert.equal(r.moodMilli, 67_500);    // 80k - 5k/h × 2.5h
  const r2 = settleDispatch({ staminaMilli: 5_000, moodMilli: 5_000 }, 10, {});
  assert.equal(r2.staminaMilli, 0);
  assert.equal(r2.moodMilli, 0);
});

test('兽栏休息：恢复体力和心情，不超上限', () => {
  const r = settleRest({ staminaMilli: 0, moodMilli: 0 }, 2, 1, {});
  assert.ok(r.staminaMilli > 0);
  assert.ok(r.moodMilli > 0);
  const full = settleRest({ staminaMilli: 99_000, moodMilli: 99_000 }, 10, 5, {});
  assert.ok(full.staminaMilli <= 100_000);
  assert.ok(full.moodMilli <= 100_000);
});

test('幂等：同输入两次结算一致', () => {
  const c = { staminaMilli: 50_000, moodMilli: 50_000 };
  assert.deepEqual(settleDispatch(c, 1, {}), settleDispatch(c, 1, {}));
  assert.deepEqual(settleRest(c, 1, 2, {}), settleRest(c, 1, 2, {}));
});
