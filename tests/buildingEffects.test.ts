/** 建筑效果测试——与 tests/building_effects_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  effectValue, fieldSlots, mineSlots, queueCap, storageCapMult, offlineCapSec, upgradeCap,
  HALL, FARM, MINE, FORGE, ALCHEMY, WAREHOUSE, TOTEM,
  type BuildingRow,
} from '../src/logic/buildingEffects.ts';

/** 与 Building.csv 同字面量（数值权威走表） */
const rows: BuildingRow[] = [
  { buildingId: 1, maxLevel: 10, effectKind: 1, effectBase: 0, effectStep: 1 },
  { buildingId: 4, maxLevel: 6, effectKind: 1, effectBase: 3, effectStep: 1 },
  { buildingId: 5, maxLevel: 6, effectKind: 1, effectBase: 1, effectStep: 1 },
  { buildingId: 7, maxLevel: 5, effectKind: 3, effectBase: 1, effectStep: 0.5 },
  { buildingId: 8, maxLevel: 5, effectKind: 3, effectBase: 1, effectStep: 0.5 },
  { buildingId: 9, maxLevel: 6, effectKind: 2, effectBase: 1, effectStep: 0.5 },
  { buildingId: 12, maxLevel: 5, effectKind: 1, effectBase: 12, effectStep: 12 },
];
const g = { OFFLINE_CAP_BASE_SEC: 43200, OFFLINE_CAP_TOTEM_SEC: 86400 };

test('效果值 = base + step × 等级；未建为 0 级', () => {
  assert.equal(effectValue([], FARM, rows), 3);                    // 灵田 lv0 → 3 田
  assert.equal(effectValue([{ buildingId: 4, level: 2 }], FARM, rows), 5);
  assert.equal(effectValue([{ buildingId: 9, level: 2 }], WAREHOUSE, rows), 2.0);
});

test('田位/矿位/队列/仓库倍率', () => {
  const b = [{ buildingId: 4, level: 1 }, { buildingId: 5, level: 2 }, { buildingId: 7, level: 3 }];
  assert.equal(fieldSlots(b, rows), 4);
  assert.equal(mineSlots(b, rows), 3);
  assert.equal(queueCap(b, FORGE, rows), Math.max(1, Math.floor(1 + 0.5 * 3)));  // 2
  assert.equal(queueCap([], ALCHEMY, rows), 1);                                  // 至少 1
  assert.equal(storageCapMult([{ buildingId: 9, level: 2 }], rows), 2.0);
  assert.equal(storageCapMult([], rows), 1.0);
});

test('图腾柱离线上限：lv0=12h，lv1=24h，再高钳制 24h', () => {
  assert.equal(offlineCapSec([], rows, g), 43200);
  assert.equal(offlineCapSec([{ buildingId: TOTEM, level: 1 }], rows, g), 86400);
  assert.equal(offlineCapSec([{ buildingId: TOTEM, level: 5 }], rows, g), 86400);
});

test('议事堂门：其余建筑上限 = min(表上限, 议事堂等级)', () => {
  const b = [{ buildingId: HALL, level: 2 }];
  assert.equal(upgradeCap(b, FARM, rows), 2);
  assert.equal(upgradeCap(b, HALL, rows), 10);          // 议事堂自身用表上限
  assert.equal(upgradeCap([], FARM, rows), 0);          // 未建议事堂 → 其他建筑锁 0
});
