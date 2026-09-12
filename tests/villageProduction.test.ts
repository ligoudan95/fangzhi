/** 村落生产结算测试（docs/15 §2 / docs/26 §3）——与 tests/village_production_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { addItem, applyOverflowDecay } from '../src/logic/inventoryLedger.ts';
import { settleCrops, type FieldState, type VillageConfig } from '../src/logic/villageProduction.ts';

const config: VillageConfig = {
  crops: new Map([
    [1, { cropId: 1, growMin: 30, yieldN: 6, outputItemId: 101, outputCount: 6 }],
    [5, { cropId: 5, growMin: 240, yieldN: 3, outputItemId: 105, outputCount: 3 }],
  ]),
  seasons: new Map([
    [0, { farmMult: 1.2 }], [1, { farmMult: 1.0 }], [2, { farmMult: 1.3 }], [3, { farmMult: 0.5 }],
  ]),
  categoryOf: new Map([[101, 3], [105, 2]]),
  storageRules: new Map([[2, 150], [3, 100]]),
  g: {
    SEASON_EPOCH_UTC_SEC: 0, OFFLINE_CAP_BASE_SEC: 43200,
    STORAGE_DECAY_PCT: 0.1, STORAGE_DECAY_PERIOD_SEC: 86400,
  },
};

test('软容量入库：可超上限保留并报告超量', () => {
  const { stacks, result } = addItem([], 101, 120, config.categoryOf, config.storageRules);
  assert.equal(result.stored, 120);
  assert.equal(result.cap, 100);
  assert.equal(result.overflow, 20);
  assert.equal(stacks.length, 1);
});

test('溢出衰减：单周期扣超额 10%，余数按 itemId 升序补齐', () => {
  const stacks = [{ itemId: 101, amount: 60 }, { itemId: 107, amount: 60 }]; // 食物类共 120，cap 100
  const { stacks: next, decayed } = applyOverflowDecay(stacks, [101, 107], 100, 1, 0.1);
  assert.equal(decayed, 2); // 超额 20 × 10% = 2
  const total = next.reduce((a, s) => a + s.amount, 0);
  assert.equal(total, 118);
});

test('衰减确定性：同输入两次结果逐字段一致', () => {
  const stacks = [{ itemId: 105, amount: 200 }];
  const a = applyOverflowDecay(stacks, [105], 150, 3, 0.1);
  const b = applyOverflowDecay(stacks, [105], 150, 3, 0.1);
  assert.deepEqual(a, b);
  // 超额 50 → 45 → 41 (40.5 floor 40? 复合见实现) — 断言总量守恒方向
  assert.ok(a.decayed > 0 && a.decayed < 50);
});

test('作物结算：30 分钟成熟，产出按季节系数（春 ×1.2）', () => {
  const fields: FieldState[] = [{ slotId: 1, cropId: 1, startedAtUtcSec: 0 }];
  const r = settleCrops(fields, 0, 1800, [], config); // t=0→1800 恰好成熟（切片边界）
  // matureAt=1800 需落在 (start,end] —— 1800 不是 300 整倍数？1800=6×300 ✓ 边界片 end=1800
  assert.equal(r.outputs.length, 1);
  assert.equal(r.outputs[0].itemId, 101);
  assert.equal(r.outputs[0].amount, Math.round(6 * 1.2)); // 春
  assert.equal(r.nextFields.length, 0); // 收获后清空
  assert.equal(r.inventory[0].amount, 7);
});

test('未到成熟不产出；倒流时间零结算', () => {
  const fields: FieldState[] = [{ slotId: 1, cropId: 1, startedAtUtcSec: 0 }];
  const early = settleCrops(fields, 0, 1700, [], config);
  assert.equal(early.outputs.length, 0);
  assert.equal(early.nextFields.length, 1);
  const rollback = settleCrops(fields, 1000, 500, [], config);
  assert.equal(rollback.outputs.length, 0);
  assert.equal(rollback.nextCursor, 1000);
});

test('离线上限：窗口截断 12h 并报告 cappedBy', () => {
  const fields: FieldState[] = [{ slotId: 1, cropId: 1, startedAtUtcSec: 0 }];
  const r = settleCrops(fields, 0, 86400, [], config);
  assert.equal(r.cappedBy, 86400 - 43200);
});

test('跨季结算：成熟点落在哪一季就用哪一季系数', () => {
  // 纪元 0：0..432000 春。430000 起种 30min → mature 431800（春）；430300 起种 → mature 432100（夏）
  const fields: FieldState[] = [
    { slotId: 1, cropId: 1, startedAtUtcSec: 430000 },       // 春季成熟 ×1.2
    { slotId: 2, cropId: 1, startedAtUtcSec: 430300 },        // 夏季成熟 ×1.0
  ];
  const r = settleCrops(fields, 430000, 432200, [], config);
  assert.equal(r.outputs.length, 2);
  const spring = r.outputs.find(o => o.season === 0);
  const summer = r.outputs.find(o => o.season === 1);
  assert.equal(spring.amount, 7);  // round(6*1.2)
  assert.equal(summer.amount, 6);  // round(6*1.0)
});

test('幂等：同输入两次结算逐字段一致', () => {
  const fields: FieldState[] = [{ slotId: 1, cropId: 5, startedAtUtcSec: 100 }];
  const a = settleCrops(fields, 0, 90000, [{ itemId: 105, amount: 100 }], config);
  const b = settleCrops(fields, 0, 90000, [{ itemId: 105, amount: 100 }], config);
  assert.deepEqual(a, b);
});
