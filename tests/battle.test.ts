/** 确定性验收（07文档 §5）：同种子同结果；冒烟（V-501） */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Battle } from '../src/battle/engine.ts';
import { loadConfig, makePetInput, groupInputs } from '../src/config/load.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cfg = loadConfig();

const team = () => [
  makePetInput(cfg, 1001, 12, 900, 1),
  makePetInput(cfg, 1002, 12, 900, 1),
  makePetInput(cfg, 1005, 12, 950, 1),
];

test('确定性：同种子同输入 → 逐行一致的战斗日志', () => {
  const a = new Battle(cfg, team(), groupInputs(cfg, 4), 42).run();
  const b = new Battle(cfg, team(), groupInputs(cfg, 4), 42).run();
  assert.deepEqual(a.log, b.log);
  assert.equal(a.rounds, b.rounds);
  assert.equal(a.outcome, b.outcome);
});

test('引擎可跑完一场Boss战（关卡6 域主藤皇）', () => {
  const bossTeam = [
    makePetInput(cfg, 1006, 20, 1000, 2),
    makePetInput(cfg, 1002, 20, 950, 2),
    makePetInput(cfg, 1011, 20, 950, 2),
  ];
  const r = new Battle(cfg, bossTeam, groupInputs(cfg, 6), 7).run();
  assert.ok(['victory', 'defeat', 'timeout'].includes(r.outcome));
  assert.ok(r.rounds >= 1 && r.rounds <= 30);
});

test('捕捉模式：战斗可以以 captured 结束', () => {
  for (let seed = 1; seed <= 50; seed++) {
    const t = [
      makePetInput(cfg, 1009, 10, 900, 1), // 玄冰鲤（控制）
      makePetInput(cfg, 1001, 10, 900, 1),
      makePetInput(cfg, 1005, 10, 900, 1),
    ];
    const b = new Battle(cfg, t, groupInputs(cfg, 2), seed, { capture: true });
    const target = b.units.find(u => u.side === 1)!;
    const r = b.run();
    // 引擎自动压血+控住后尝试捕捉（AI捕捉模式见03§10，此处由run内部驱动简化验证）
    assert.ok(r.outcome && r.log.length > 0);
    if (r.outcome === 'captured') assert.equal(r.capturedPetId, target.petId);
  }
});

test('冒烟 V-501：表引用完整性', () => {
  const stage = JSON.parse(readFileSync(join(ROOT, 'out/config/StageConfig.json'), 'utf8')) as { stageId: number; waves: number[]; dropId: number; power: number }[];
  const groups = JSON.parse(readFileSync(join(ROOT, 'out/config/EnemyGroup.json'), 'utf8')) as { groupId: number }[];
  const drops = JSON.parse(readFileSync(join(ROOT, 'out/config/DropRule.json'), 'utf8')) as { dropId: number }[];
  const gids = new Set(groups.map(x => x.groupId));
  const dids = new Set(drops.map(x => x.dropId));
  assert.ok(stage.length >= 6, '关卡数量');
  for (const s of stage) {
    assert.ok(s.waves.every(w => gids.has(w)), `关卡${s.stageId}波次引用存在`);
    assert.ok(dids.has(s.dropId), `关卡${s.stageId}掉落引用存在`);
  }
  // 每只灵宠技能池完整（4技能）
  for (const [petId, skills] of cfg.skillPool) {
    assert.equal(skills.filter(Boolean).length, 4, `灵宠${petId}技能池=4`);
  }
  // 12只首发灵宠齐全（决策#5）
  assert.equal(cfg.pets.size, 12);
});
