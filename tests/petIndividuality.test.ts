/** 灵宠个体化测试——与 tests/pet_individuality_test.gd 同口径 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { rollAptitudes, rollNature, natureModifiers, breakthroughCost } from '../src/logic/petIndividuality.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pets = JSON.parse(readFileSync(join(ROOT, 'out/config/PetBase.json'), 'utf8')) as Array<{
  petId: number; name: string; aptitudes: number[]; natures: string; breaks: string;
}>;
const g = JSON.parse(readFileSync(join(ROOT, 'out/config/GlobalConst.json'), 'utf8'));

test('资质 roll：同种子确定一致，不同种子有差异', () => {
  const pet = pets.find(p => p.petId === 1001)!;
  const a1 = rollAptitudes(pet, 42);
  const a2 = rollAptitudes(pet, 42);
  const a3 = rollAptitudes(pet, 43);
  assert.deepEqual(a1, a2);
  assert.ok(JSON.stringify(a1) !== JSON.stringify(a3));
  assert.ok(a1.atk >= pet.aptitudes[0] && a1.atk <= pet.aptitudes[1]);
  assert.ok(a1.def >= pet.aptitudes[2] && a1.def <= pet.aptitudes[3]);
  assert.ok(a1.hp >= pet.aptitudes[4] && a1.hp <= pet.aptitudes[5]);
  assert.ok(a1.spd >= pet.aptitudes[6] && a1.spd <= pet.aptitudes[7]);
  assert.ok(a1.mag >= pet.aptitudes[8] && a1.mag <= pet.aptitudes[9]);
});

test('资质 roll：多种子覆盖范围合理', () => {
  const pet = pets.find(p => p.petId === 1002)!;
  const atks: number[] = [];
  for (let seed = 1; seed <= 100; seed++) {
    const a = rollAptitudes(pet, seed);
    atks.push(a.atk);
  }
  const min = Math.min(...atks), max = Math.max(...atks);
  assert.ok(min >= pet.aptitudes[0] && max <= pet.aptitudes[1]);
  assert.ok(max > min, '范围内应有差异');
});

test('性格 roll：同种子确定，从池中选', () => {
  const pet = pets.find(p => p.petId === 1001)!;
  const pool = Array.isArray(pet.natures) ? pet.natures : pet.natures.split(";");
  const n1 = rollNature(pet, 42);
  const n2 = rollNature(pet, 42);
  assert.equal(n1, n2);
  assert.ok(pool.includes(n1), `"${n1}" 在池中`);
});

test('性格修正表：已定义性格返回修正', () => {
  assert.deepEqual(natureModifiers('沉稳'), { def: 0.05, spd: -0.03 });
  assert.deepEqual(natureModifiers('敏捷'), { spd: 0.10, def: -0.04 });
  assert.deepEqual(natureModifiers('未知'), {});
});

test('突破消耗：各阶段等级门槛与修为递增', () => {
  const pet = pets.find(p => p.petId === 1001)!;
  const c1 = breakthroughCost(pet, 0, g);
  assert.equal(c1.can, true);
  assert.equal(c1.requiredLevel, g.BRK_LV2);
  assert.ok(c1.xiuCost! > 0);
  const c2 = breakthroughCost(pet, 1, g);
  assert.equal(c2.requiredLevel, g.BRK_LV3);
  assert.ok(c2.xiuCost! > c1.xiuCost!);
  const c5 = breakthroughCost(pet, 4, g);
  assert.equal(c5.can, false);
});

test('突破阶段名：从链中取', () => {
  const pet = pets.find(p => p.petId === 1001)!;
  const chain = Array.isArray(pet.breaks) ? pet.breaks : pet.breaks.split(';');
  const c = breakthroughCost(pet, 0, g);
  assert.equal(c.stageName, chain[1]);
});
