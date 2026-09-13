/** 灵宠成长测试——与 tests/pet_growth_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { feedCost, levelCap, feed, breakthrough } from '../src/logic/petGrowth.ts';

const g = {
  BRK_LV2: 15, BRK_LV3: 40, BRK_LV4: 80, BRK_LV5: 120,
  PET_FEED_XIU_BASE: 50, PET_FEED_XIU_STEP: 10,
};
const petRow = { aptitudes: [], natures: '', breaks: '幼兽;成兽;开灵;完全体;太古体' };

test('喂养消耗：base + step × (level-1)', () => {
  assert.equal(feedCost(1, g), 50);
  assert.equal(feedCost(15, g), 190);
});

test('等级帽 = 下一突破门槛', () => {
  assert.equal(levelCap(0, g), 15);
  assert.equal(levelCap(1, g), 40);
  assert.equal(levelCap(2, g), 80);
  assert.equal(levelCap(4, g), 120);
  assert.equal(levelCap(9, g), 120);
});

test('喂养：正常/修为不足/等级帽', () => {
  const r = feed({ level: 1, realmBreaks: 0 }, 100, g);
  assert.equal(r.ok, true);
  assert.equal(r.cost, 50);
  assert.equal(r.level, 2);
  const r2 = feed({ level: 3, realmBreaks: 0 }, 10, g);
  assert.equal(r2.ok, false);
  assert.ok(r2.reason.includes('修为不足'));
  const r3 = feed({ level: 15, realmBreaks: 0 }, 99999, g);
  assert.equal(r3.ok, false);
  assert.ok(r3.reason.includes('突破'));
});

test('突破：等级门/修为消耗/封顶', () => {
  const r = breakthrough({ level: 10, realmBreaks: 0 }, petRow, 99999, g);
  assert.equal(r.ok, false);
  assert.ok(r.reason.includes('等级不足'));
  const r2 = breakthrough({ level: 15, realmBreaks: 0 }, petRow, 600, g);
  assert.equal(r2.ok, true);
  assert.equal(r2.cost, 500);          // 500 × 1.6^0
  assert.equal(r2.realmBreaks, 1);
  assert.equal(breakthrough({ level: 15, realmBreaks: 0 }, petRow, 400, g).ok, false);
  assert.equal(breakthrough({ level: 120, realmBreaks: 4 }, petRow, 99999, g).ok, false);
});
