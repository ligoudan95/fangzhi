/** 经济模拟/图鉴收集测试 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { simulate, PROFILE } from '../src/logic/economySim.ts';
import { collectedIds, completionRatio, luckBonus } from '../src/logic/codexSystem.ts';

const seasons = new Map([[0, { farmMult: 1.2, mineMult: 1.0 }], [1, { farmMult: 1.0, mineMult: 1.0 }], [2, { farmMult: 1.3, mineMult: 1.0 }], [3, { farmMult: 0.5, mineMult: 0.7 }]]);

test('经济模拟：标准档 30 天产出兽贝余额为正', () => {
  const r = simulate(PROFILE.NORMAL as 1, 30, 5, { seasons });
  assert.equal(r.dailyLog.length, 30);
  assert.ok(r.inventory['兽贝'] > 0, `余额 ${r.inventory['兽贝']} 应为正`);
});

test('经济模拟：放置档产出低于活跃档', () => {
  const idle = simulate(PROFILE.IDLE as 0, 30, 5, { seasons });
  const active = simulate(PROFILE.ACTIVE as 2, 30, 5, { seasons });
  assert.ok(active.inventory['兽贝'] > idle.inventory['兽贝']);
});

test('经济模拟：冬季产出最低（×0.5）', () => {
  const r = simulate(PROFILE.NORMAL as 1, 20, 5, { seasons });
  const springHarvests = r.dailyLog.filter(d => d.season === 0).map(d => d.harvest);
  const winterHarvests = r.dailyLog.filter(d => d.season === 3).map(d => d.harvest);
  const avgSpring = springHarvests.reduce((a, b) => a + b, 0) / springHarvests.length;
  const avgWinter = winterHarvests.reduce((a, b) => a + b, 0) / winterHarvests.length;
  assert.ok(avgWinter < avgSpring);
});

test('经济模拟：确定性（同输入同输出）', () => {
  const a = simulate(PROFILE.NORMAL as 1, 30, 5, { seasons });
  const b = simulate(PROFILE.NORMAL as 1, 30, 5, { seasons });
  assert.deepEqual(a.inventory, b.inventory);
});

test('图鉴：3/12 完成度 → 幸运+50', () => {
  const pets = [{ petId: 1001 }, { petId: 1002 }, { petId: 1003 }];
  assert.equal(completionRatio(pets, [1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012]), 0.25);
  assert.equal(luckBonus(pets, [1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012]), 50);
});
