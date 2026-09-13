/** 配方生产测试——与 tests/recipe_craft_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseInputs, startCraft, settleCrafts, type RecipeRow } from '../src/logic/recipeCraft.ts';

const recipes = new Map<number, RecipeRow>([
  [4, { recipeId: 4, station: 1, inputs: '201:2;206:2', outputItemId: 206, outputCount: 1, durationMin: 30 }],
  [1, { recipeId: 1, station: 2, inputs: '101:3', outputItemId: 107, outputCount: 1, durationMin: 10 }],
]);
const recipeOf = (id: number) => recipes.get(id);
const categoryOf = new Map([[101, 3], [107, 3], [201, 1], [206, 5]]);
const rules = new Map([[1, 200], [3, 100], [5, 50]]);

test('inputs 解析：合法段保留，非法段跳过', () => {
  assert.deepEqual(parseInputs('201:2;206:2'), [{ itemId: 201, count: 2 }, { itemId: 206, count: 2 }]);
  assert.deepEqual(parseInputs(''), []);
  assert.deepEqual(parseInputs('a:b;0:1;201:0;201:-1;301:2'), [{ itemId: 301, count: 2 }]);
});

test('开始生产：足料扣料入队；缺料/队满拒绝', () => {
  const inv = [{ itemId: 201, amount: 5 }, { itemId: 206, amount: 2 }];
  const r = startCraft([], 4, '201:2;206:2', 1000, inv, 2);
  assert.equal(r.error, '');
  assert.equal(r.jobs.length, 1);
  assert.deepEqual(r.inventory, [{ itemId: 201, amount: 3 }]);   // 206 扣光移除
  const r2 = startCraft(r.jobs, 4, '201:2;206:2', 1100, r.inventory, 2);
  assert.equal(r2.error, '材料不足');
  const r3 = startCraft([{ recipeId: 1, startedAtUtcSec: 0 }, { recipeId: 1, startedAtUtcSec: 1 }], 4, '201:2;206:2', 1200, inv, 2);
  assert.equal(r3.error, '队列已满');
});

test('结算：未到期保留；到时产出并移除任务；幂等', () => {
  const jobs = [{ recipeId: 4, startedAtUtcSec: 0 }];
  const half = settleCrafts(jobs, 29 * 60, [], recipeOf, categoryOf, rules, 1.0);
  assert.equal(half.nextJobs.length, 1);
  assert.equal(half.outputs.length, 0);
  const done = settleCrafts(jobs, 30 * 60, [], recipeOf, categoryOf, rules, 1.0);
  assert.equal(done.nextJobs.length, 0);
  assert.deepEqual(done.outputs, [{ itemId: 206, amount: 1 }]);
  assert.deepEqual(done.inventory, [{ itemId: 206, amount: 1 }]);
  const again = settleCrafts(done.nextJobs, 99999, done.inventory, recipeOf, categoryOf, rules, 1.0);
  assert.equal(again.outputs.length, 0);   // 幂等：无重复产出
});

test('仓库倍率：capMult 抬高软上限', () => {
  const recipes2 = new Map([[1, recipes.get(1)!]]);
  const inv = [{ itemId: 107, amount: 95 }];   // 分类 3 基础 cap=100
  const r = settleCrafts([{ recipeId: 1, startedAtUtcSec: 0 }], 600, inv, (id) => recipes2.get(id), categoryOf, rules, 1.5);
  assert.equal(r.outputs.length, 1);
  assert.equal(r.inventory[0].amount, 96);
});
