/** 装备属性修正测试——与 tests/equip_stats_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, loadEquipmentConfig } from '../src/config/load.ts';
import { equippedMods, type EquipSetRow } from '../src/logic/equipStats.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cfg = loadConfig();
const g = cfg.g;
const ec = loadEquipmentConfig();
const setsRaw = JSON.parse(
  readFileSync(resolve(ROOT, 'resources/config/EquipSet.json'), 'utf8'),
) as EquipSetRow[];

function item(equipId: number, instance: string) {
  return {
    instanceId: instance, equipId, quality: 0, level: 0,
    rollSeed: 12345, identified: true, enhanceLevel: 0,
  };
}

test('主属性平面加成：武器 101 白品 0 级 = atk+32', () => {
  const mods = equippedMods({ equips: { 1: 'a' } }, [item(101, 'a')], ec, setsRaw, g);
  assert.equal(mods.flat.atk ?? 0, 32);
  assert.equal(mods.ratio.atk ?? 0, 0);
});

test('强化倍率：+3 → ×1.15 → 37', () => {
  const it = { ...item(101, 'a'), enhanceLevel: 3 };
  const mods = equippedMods({ equips: { 1: 'a' } }, [it], ec, setsRaw, g);
  assert.equal(mods.flat.atk ?? 0, 37);
});

test('未鉴定与幽灵实例跳过', () => {
  const unid = { ...item(101, 'a'), identified: false };
  const mods = equippedMods({ equips: { 1: 'a', 2: 'ghost' } }, [unid], ec, setsRaw, g);
  assert.equal(Object.keys(mods.flat).length, 0);
});

test('套装：2 件 spd+12% 进 ratio；3 件特殊键进 special', () => {
  const items = [item(101, 'w'), item(301, 't'), item(201, 'a')];
  const two = equippedMods({ equips: { 1: 'w', 3: 't' } }, items, ec, setsRaw, g);
  assert.equal(two.ratio.spd ?? 0, 0.12);
  assert.equal(two.activeSets.length, 1);
  const three = equippedMods({ equips: { 1: 'w', 2: 'a', 3: 't' } }, items, ec, setsRaw, g);
  assert.equal(three.activeSets[0].tier, 3);
  assert.equal(three.special.length, 1);
  assert.ok(three.special[0].includes('狼魂'));
  assert.equal(three.ratio.spd ?? 0, 0.12);
});
