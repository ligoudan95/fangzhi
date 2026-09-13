/**
 * 对拍期望日志生成（docs/13 §6）：用 TS 数值基准引擎按种子清单跑三个场景，
 * 产出 out/parity/expected/seed_<n>.log；Godot 侧 tests/parity_runner.gd
 * 用相同场景与种子逐行 diff。种子清单 tools/parity/seeds.json 入 Git，日志产物不入库。
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { Battle } from '../../src/battle/engine.ts';
import { loadConfig, loadEquipmentConfig, makePetInput, groupInputs } from '../../src/config/load.ts';
import { emptyPityState, resolveIdentification, resolveSettlement, type PityState } from '../../src/equipment/drop.ts';
import { settleCrops, type FieldState, type ItemStack as FarmStack, type VillageConfig } from '../../src/logic/villageProduction.ts';
import { settleMines } from '../../src/logic/mineProduction.ts';
import { settleMissed } from '../../src/logic/beastTide.ts';
import { fieldSlots, mineSlots, queueCap, storageCapMult, offlineCapSec, upgradeCap, FARM, FORGE, type BuildingRow } from '../../src/logic/buildingEffects.ts';
import { startCraft, settleCrafts } from '../../src/logic/recipeCraft.ts';

const ROOT = join(import.meta.dirname, '..', '..');

/** 事件摘要（docs/10 §8.1）：字段顺序固定，与 tests/parity_runner.gd 同格式逐行对拍 */
function evDigest(e: Record<string, unknown>): string {
  switch (e.t) {
    case 'start':
      return '[ev] start units=' + (e.units as Array<Record<string, unknown>>)
        .map(x => `${x.u}:${x.s}:${x.n}:${x.hp}:${x.el}`).join(';');
    case 'round': return `[ev] round r=${e.r}`;
    case 'cast': return `[ev] cast r=${e.r} u=${e.u} s=${e.s} tg=${(e.tg as number[]).join('|')}`;
    case 'hit': return `[ev] hit u=${e.u} d=${e.d} hp=${e.hp} c=${e.c}`;
    case 'dodge': return `[ev] dodge u=${e.u}`;
    case 'heal': return `[ev] heal u=${e.u} a=${e.a} hp=${e.hp}`;
    case 'shield': return `[ev] shield u=${e.u} a=${e.a}`;
    case 'buff': return `[ev] buff u=${e.u} b=${e.b} st=${e.st}`;
    case 'death': return `[ev] death u=${e.u}`;
    case 'sub': return `[ev] sub u=${e.u} n=${e.n} s=${e.s}`;
    case 'cap': return `[ev] cap u=${e.u} tu=${e.tu} rt=${e.rt} ok=${e.ok}`;
    case 'end': return `[ev] end o=${e.o} r=${e.r}`;
    default: return `[ev] ${String(e.t)}`;
  }
}
const cfg = loadConfig();
const g = cfg.g;
const seeds: number[] = JSON.parse(readFileSync(join(ROOT, 'tools/parity/seeds.json'), 'utf8'));
const OUT_DIR = join(ROOT, 'out', 'parity', 'expected');

mkdirSync(OUT_DIR, { recursive: true });

for (const seed of seeds) {
  const lines: string[] = [`### seed=${seed}`];

  // 场景1：关卡4 黑风林·雾深处（标准 3v3）
  {
    const b = new Battle(
      cfg,
      [
        makePetInput(cfg, 1001, 12, 900, 1),
        makePetInput(cfg, 1002, 12, 900, 1),
        makePetInput(cfg, 1005, 12, 950, 1),
      ],
      groupInputs(cfg, 4),
      seed,
    );
    const r = b.run();
    lines.push(`[stage4] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
    lines.push(...r.events.map(evDigest));
  }

  // 场景2：关卡6 Boss 域主藤皇（高压战斗，多机制覆盖）
  {
    const b = new Battle(
      cfg,
      [
        makePetInput(cfg, 1006, 20, 1000, 2),
        makePetInput(cfg, 1002, 20, 950, 2),
        makePetInput(cfg, 1011, 20, 950, 2),
      ],
      groupInputs(cfg, 6),
      seed,
    );
    const r = b.run();
    lines.push(`[stage6] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
    lines.push(...r.events.map(evDigest));
  }

  // 场景3：捕捉战（关卡2 外围藤影，玄冰鲤控场）——覆盖 tryCapture 与捕捉率日志
  {
    const b = new Battle(
      cfg,
      [
        makePetInput(cfg, 1009, 10, 900, 1),
        makePetInput(cfg, 1001, 10, 900, 1),
        makePetInput(cfg, 1005, 10, 950, 1),
      ],
      groupInputs(cfg, 2),
      seed,
      { capture: true },
    );
    b.tryCapture(1, g.CAP_GOURD_JADE, g.CAP_Q3);
    if (!b.outcome) b.tryCapture(1, g.CAP_GOURD_WOOD, g.CAP_Q1);
    const r = b.run();
    lines.push(`[capture] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
    lines.push(...r.events.map(evDigest));
  }

  // 场景4：装备掉落（M3）——品质/幸运/保底连锁/词条/鉴定展开（与 parity_runner.gd 同字面量）
  {
    const ec = loadEquipmentConfig();
    const drop = (seq: number, dropId: number, count: number, level: number, luck: number, pity: PityState) =>
      resolveSettlement({ rootSeed: seed, settlementSeq: seq, dropId, dropCount: count, monsterLevel: level, luckValue: luck, pityState: pity }, ec, g);

    lines.push(...drop(1001, 1, 2, 12, 0, emptyPityState()).canonicalLog);

    const pity14: PityState = { schemaVersion: 1, counters: { '2': 14 } };
    const b1 = drop(1002, 2, 3, 20, 100, pity14);
    lines.push(...b1.canonicalLog);
    lines.push(...drop(1003, 2, 3, 20, 100, b1.pityAfter).canonicalLog);

    const c = drop(1004, 3, 1, 30, 250, emptyPityState());
    lines.push(...c.canonicalLog);
    const view = resolveIdentification(c.items[0], ec, g);
    lines.push(
      `[loot_ident] instanceId=${c.items[0].instanceId} mainValueMicro=${view.mainValueMicro}` +
      ` affixCount=${view.affixes.length} firstAffix=${view.affixes.length ? view.affixes[0].affixId : -1}` +
      ` firstMicro=${view.affixes.length ? view.affixes[0].valueMicro : -1}`,
    );
  }

  // 场景5：村落作物结算（M4 尾项）——跨季/离线上限/溢出衰减（与 parity_runner.gd 同字面量）
  {
    const vconfig: VillageConfig = {
      crops: new Map([
        [1, { cropId: 1, growMin: 30, yieldN: 6, outputItemId: 101, outputCount: 6 }],
        [5, { cropId: 5, growMin: 240, yieldN: 3, outputItemId: 105, outputCount: 3 }],
      ]),
      seasons: new Map([[0, { farmMult: 1.2 }], [1, { farmMult: 1.0 }], [2, { farmMult: 1.3 }], [3, { farmMult: 0.5 }]]),
      categoryOf: new Map([[101, 3], [105, 2]]),
      storageRules: new Map([[2, 150], [3, 100]]),
      g: { SEASON_EPOCH_UTC_SEC: 0, OFFLINE_CAP_BASE_SEC: 43200, STORAGE_DECAY_PCT: 0.1, STORAGE_DECAY_PERIOD_SEC: 86400 },
    };
    const farmScenario = (fields: FieldState[], cursor: number, now: number, inv: FarmStack[]) => {
      const r = settleCrops(fields, cursor, now, inv, vconfig);
      lines.push(`[farm] cursor=${cursor} now=${now} cappedBy=${r.cappedBy} outputs=${r.outputs.length} fields=${r.nextFields.length}`);
      for (const o of r.outputs) lines.push(`[farm_out] item=${o.itemId} amount=${o.amount} season=${o.season}`);
      for (const s of r.inventory) lines.push(`[farm_inv] item=${s.itemId} amount=${s.amount}`);
    };
    farmScenario(
      [{ slotId: 1, cropId: 1, startedAtUtcSec: 430000 }, { slotId: 2, cropId: 5, startedAtUtcSec: 100 }],
      430000, 432200, [],
    );
    farmScenario(
      [{ slotId: 1, cropId: 1, startedAtUtcSec: 0 }],
      0, 90000, [{ itemId: 101, amount: 120 }],
    );
  }

  // 场景6：建筑效果（Phase B）——效果值/田位/矿位/队列/仓库倍率/图腾上限/议事堂门
  {
    const rows: BuildingRow[] = [
      { buildingId: 1, maxLevel: 10, effectKind: 1, effectBase: 0, effectStep: 1 },
      { buildingId: 4, maxLevel: 6, effectKind: 1, effectBase: 3, effectStep: 1 },
      { buildingId: 5, maxLevel: 6, effectKind: 1, effectBase: 1, effectStep: 1 },
      { buildingId: 7, maxLevel: 5, effectKind: 3, effectBase: 1, effectStep: 0.5 },
      { buildingId: 9, maxLevel: 6, effectKind: 2, effectBase: 1, effectStep: 0.5 },
      { buildingId: 12, maxLevel: 5, effectKind: 1, effectBase: 12, effectStep: 12 },
    ];
    const b = [
      { buildingId: 4, level: 2 }, { buildingId: 5, level: 1 }, { buildingId: 7, level: 3 },
      { buildingId: 9, level: 2 }, { buildingId: 12, level: 1 }, { buildingId: 1, level: 2 },
    ];
    const bg = { OFFLINE_CAP_BASE_SEC: 43200, OFFLINE_CAP_TOTEM_SEC: 86400 };
    lines.push(
      `[build] farmSlots=${fieldSlots(b, rows)} mineSlots=${mineSlots(b, rows)}` +
      ` forgeCap=${queueCap(b, FORGE, rows)} warehouseMult=${storageCapMult(b, rows).toFixed(2)}` +
      ` totemCap=${offlineCapSec(b, rows, bg)} hallGate=${upgradeCap(b, FARM, rows)}`,
    );
  }

  // 场景7：配方生产（Phase B）——入队扣料/未到期/到时产出/仓库倍率（与 parity_runner.gd 同字面量）
  {
    const recipes = new Map([
      [4, { recipeId: 4, station: 1, inputs: '201:2;206:2', outputItemId: 206, outputCount: 1, durationMin: 30 }],
    ]);
    const recipeOf = (id: number) => recipes.get(id);
    const categoryOf = new Map([[201, 1], [206, 5]]);
    const rules = new Map([[1, 200], [5, 50]]);
    const inv0 = [{ itemId: 201, amount: 5 }, { itemId: 206, amount: 2 }];
    const invStr = (inv: { itemId: number; amount: number }[]) =>
      inv.length ? inv.map(s => `${s.itemId}:${s.amount}`).join(';') : '-';
    const s = startCraft([], 4, '201:2;206:2', 1000, inv0, 2);
    lines.push(`[recipe_start] error=${s.error} jobs=${s.jobs.length} inv=${invStr(s.inventory)}`);
    const half = settleCrafts(s.jobs, 1000 + 29 * 60, s.inventory, recipeOf, categoryOf, rules, 1.0);
    lines.push(`[recipe_settle_half] jobs=${half.nextJobs.length} outputs=${half.outputs.length}`);
    const done = settleCrafts(s.jobs, 1000 + 30 * 60, s.inventory, recipeOf, categoryOf, rules, 2.0);
    lines.push(`[recipe_settle_done] jobs=${done.nextJobs.length} outputs=${done.outputs.length} inv=${invStr(done.inventory)}`);
  }

  // 场景8：矿场结算（Phase B）——切片×季节系数/分数结转/灵晶入钱包（与 parity_runner.gd 同字面量）
  {
    const mconfig = {
      mines: new Map([
        [1, { mineId: 1, ironRate: 10, crystalRate: 2, refinedRate: 1, spiritRate: 1 }],
        [2, { mineId: 2, ironRate: 6, crystalRate: 3, refinedRate: 0, spiritRate: 2 }],
      ]),
      seasons: new Map([[0, { mineMult: 1.2 }], [1, { mineMult: 1.0 }], [2, { mineMult: 1.3 }], [3, { mineMult: 0.5 }]]),
      categoryOf: new Map([[201, 1], [202, 1], [203, 1]]),
      storageRules: new Map([[1, 200]]),
      g: { SEASON_EPOCH_UTC_SEC: 0, OFFLINE_CAP_BASE_SEC: 43200 },
    };
    const jobs = [
      { slotId: 1, mineId: 1, startedAtUtcSec: 430000, assignedPetInstanceIds: [] },
      { slotId: 2, mineId: 2, startedAtUtcSec: 430000, assignedPetInstanceIds: [] },
      { slotId: 3, mineId: 1, startedAtUtcSec: 430000, assignedPetInstanceIds: [1], efficiency: 0.5 },
    ];
    const r = settleMines(jobs, 430000, 444400, { beastShell: 5, spiritCrystal: 50, totemEmblem: 0 }, [], mconfig);
    lines.push(`[mine] cursor=430000 now=444400 outputs=${r.outputs.length}` +
      ` wallet=spirit:${r.wallet.spiritCrystal},beast:${r.wallet.beastShell},totem:${r.wallet.totemEmblem}` +
      ` inv=${r.inventory.length ? r.inventory.map(s => `${s.itemId}:${s.amount}`).join(';') : '-'}`);
    for (const o of r.outputs) lines.push(`[mine_out] item=${o.itemId} amount=${o.amount}`);
  }

  // 场景9：兽潮错过补结算（Phase B）——波次枚举/确定性种子/逐波战斗（与 parity_runner.gd 同字面量）
  {
    const team = [
      makePetInput(cfg, 1001, 12, 900, 1),
      makePetInput(cfg, 1002, 12, 900, 1),
      makePetInput(cfg, 1005, 12, 950, 1),
    ];
    const t = settleMissed(864000000, 864172800, 28800, seed, team, {}, cfg, g);
    lines.push(`[beast] cursor=864000000 now=864172800 tz=28800 waves=${t.waves.length} settled=${t.settledCount}`);
    for (const w of t.waves) lines.push(`[beast_wave] utc=${w.waveUtcSec} outcome=${w.outcome} rounds=${w.rounds}`);
  }

  // 场景10：套装特殊机制（docs/08 §7）——setBonuses 通道全键覆盖的确定性战斗
  {
    const team = [
      { ...makePetInput(cfg, 1001, 12, 900, 1), setBonuses: { dmg_first: 0.4, cd_reduce: 1, rage_crit: 20, rage_double: 2 } },
      { ...makePetInput(cfg, 1002, 12, 900, 1), setBonuses: { heal: 0.2, shield_heal: 0.15 } },
      { ...makePetInput(cfg, 1006, 12, 900, 1), setBonuses: { dmg_fire: 0.15, detonate_splash: 0.5, dmg_frozen: 0.5, freeze_chance: 0.15 } },
    ];
    const b = new Battle(cfg, team, groupInputs(cfg, 4), seed);
    const r = b.run();
    lines.push(`[setbonus] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
    lines.push(...r.events.map(evDigest));
  }

  writeFileSync(join(OUT_DIR, `seed_${seed}.log`), lines.join('\n') + '\n');
}

console.log(`对拍期望日志已生成：${seeds.length} 个种子 × 10 场景 → out/parity/expected/`);
