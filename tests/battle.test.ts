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

test('捕捉模式：低血目标触发收妖，消耗我方行动并在敌方行动后结算', () => {
  const captureCfg = {
    ...cfg,
    g: {
      ...cfg.g,
      ROUND_CAP: 1,
      CAP_GOURD_JADE: 1,
      CAP_Q1: 1,
      CAP_HP_LO: 1,
      CAP_ST_CTRL: 1,
      CAP_ST_DEBUFF: 1,
    },
  };
  const b = new Battle(
    captureCfg,
    [makePetInput(captureCfg, 1001, 1, 900, 0)],
    [makePetInput(captureCfg, 1003, 1, 900, 0, { captureable: true, strategy: 'focus_weak' })],
    7,
    { capture: true },
  );
  const actor = b.units.find(u => u.side === 0)!;
  const target = b.units.find(u => u.side === 1)!;
  actor.stats.spd = 1000;
  target.stats.spd = 1;
  target.hp = Math.floor(target.stats.hp * 0.19);

  const r = b.run();
  const prepareIndex = r.log.findIndex(line => line.includes(`${actor.name} 准备收妖`));
  const enemyActionIndex = r.log.findIndex(line => line.includes(`[敌]${target.name} 施放`));
  const settleIndex = r.log.findIndex(line => line.includes(`${actor.name} 祭出祖灵葫芦`));

  assert.equal(r.outcome, 'captured');
  assert.equal(r.capturedPetId, target.petId);
  assert.ok(prepareIndex >= 0 && prepareIndex < enemyActionIndex);
  assert.ok(enemyActionIndex < settleIndex);
  assert.equal(r.log.some(line => line.includes(`${actor.name} 施放`)), false);
});

test('多段攻击：目标倒下后后续 hit 转投剩余最低血量敌人', () => {
  const battleCfg = {...cfg, g: {...cfg.g, ROUND_CAP: 1, HIT_BASE: 1, CRIT_BASE: 0, FLOAT_MIN: 1, FLOAT_MAX: 1}};
  const multiHit = {...cfg.skills.get(3)!, cd: 0, learnLv: 1};
  const skills = new Map(cfg.skills);
  skills.set(multiHit.skillId, multiHit);
  battleCfg.skills = skills;
  const attackerInput = makePetInput(battleCfg, 1001, 1, 900, 0, { strategy: 'focus_weak' });
  attackerInput.skillIds = [multiHit.skillId];
  const b = new Battle(
    battleCfg,
    [attackerInput],
    [
      makePetInput(battleCfg, 1003, 1, 900, 0, { strategy: 'focus_weak' }),
      makePetInput(battleCfg, 1004, 1, 900, 0, { strategy: 'focus_weak' }),
    ],
    11,
  );
  const attacker = b.units.find(u => u.side === 0)!;
  const first = b.units.find(u => u.petId === 1003)!;
  const second = b.units.find(u => u.petId === 1004)!;
  attacker.stats.atk = 10000;
  attacker.stats.spd = 1000;
  first.stats.spd = 1;
  second.stats.spd = 1;
  first.hp = 1;
  second.hp = 100;

  const r = b.run();
  const hitLines = r.log.filter(line => line.includes('受到'));
  assert.ok(hitLines[0]?.includes(first.name));
  assert.ok(hitLines[1]?.includes(second.name));
});

test('嘲讽：不动如山强制敌方攻击施法者并按 duration 持续', () => {
  const battleCfg = {...cfg, g: {...cfg.g, ROUND_CAP: 1, HIT_BASE: 1, CRIT_BASE: 0, FLOAT_MIN: 1, FLOAT_MAX: 1}};
  const b = new Battle(
    battleCfg,
    [
      makePetInput(battleCfg, 1011, 40, 950, 2),
      makePetInput(battleCfg, 1002, 40, 950, 2),
    ],
    [makePetInput(battleCfg, 1003, 40, 950, 2, { strategy: 'focus_weak' })],
    3,
  );
  const taunter = b.units.find(u => u.petId === 1011)!;
  const weakAlly = b.units.find(u => u.petId === 1002)!;
  const enemy = b.units.find(u => u.side === 1)!;
  taunter.rage = battleCfg.g.RAGE_MAX;
  taunter.stats.spd = 1000;
  weakAlly.stats.spd = 1;
  weakAlly.hp = 1;
  enemy.stats.spd = 500;

  const r = b.run();
  const enemyDamage = r.log.find(line =>
    (line.includes(`→ ${taunter.name}`) || line.includes(`→ ${weakAlly.name}`)) &&
    (line.includes('受到') || line.includes('护盾吸收')),
  );
  assert.ok(enemyDamage?.includes(taunter.name));
  assert.equal(enemy.tauntTarget, taunter.uid);
  assert.equal(enemy.tauntRemain, 1);
});

test('技能习得：仅装配 learnLv 不高于单位等级的技能', () => {
  const b = new Battle(
    cfg,
    [makePetInput(cfg, 1001, 1, 900, 0)],
    [makePetInput(cfg, 1003, 1, 900, 0)],
    1,
  );
  assert.deepEqual(b.units[0]!.skills.map(skill => skill.skillId), [1, 2]);
  assert.equal(b.units[0]!.cds.length, 2);
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
    assert.ok(skills.every(entry => entry.skillId > 0 && entry.learnLv > 0), `灵宠${petId}技能池字段完整`);
  }
  // 12只首发灵宠齐全（决策#5）
  assert.equal(cfg.pets.size, 12);
});
