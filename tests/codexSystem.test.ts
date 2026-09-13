/** 图鉴收集测试——与 tests/codex_system_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { collectedIds, completionRatio, luckBonus, codexEntries } from '../src/logic/codexSystem.ts';

const allIds = [1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012];
const rows = allIds.map(id => ({ petId: id, name: `宠${id}`, element: 1, quality: 2 }));

test('收集去重：同 petId 多只算 1', () => {
  const pets = [{ petId: 1001 }, { petId: 1001 }, { petId: 1002 }];
  assert.equal(collectedIds(pets).length, 2);
});

test('完成度：3/12 = 0.25', () => {
  const pets = [{ petId: 1001 }, { petId: 1002 }, { petId: 1003 }];
  assert.equal(completionRatio(pets, allIds), 0.25);
});

test('幸运加成：25% 完成度 → floor(0.25/0.05)*10 = 50', () => {
  const pets = [{ petId: 1001 }, { petId: 1002 }, { petId: 1003 }];
  assert.equal(luckBonus(pets, allIds), 50);
});

test('图鉴条目：12 条，未收集标记 false', () => {
  const pets = [{ petId: 1001 }];
  const entries = codexEntries(pets, rows);
  assert.equal(entries.length, 12);
  assert.equal(entries.find(e => e.petId === 1001)?.captured, true);
  assert.equal(entries.find(e => e.petId === 1002)?.captured, false);
});
