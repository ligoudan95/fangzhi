/**
 * 装备掉落 resolver（docs/08 M3 Phase 0 契约）——纯函数，无 IO、无战斗实例依赖。
 * 生成顺序：品质（自然 roll → 保底覆盖）→ 模板 → 装备等级 → 词条数 → 词条无放回选择 → 词条值。
 * Phase 0 口径（docs/14 已定）：
 * - dropCount = guaranteed attempts（来源系数/equipDropChance 待数值批准后再接）
 * - pityUnit = settlement：一次结算至多推进一格；达到阈值强制至少一件目标品质
 * - quality 作为实例已发生结果持久化；未鉴定仅隐藏，不重 roll
 * - 橙红威能行为延期（已知缺口）；套装/洗炼/强化不在本闭环
 */
import type { G } from '../battle/stats.ts';
import {
  TAG_AFFIX_COUNT, TAG_AFFIX_SELECT, TAG_AFFIX_VALUE, TAG_LEVEL, TAG_PITY_INDEX,
  TAG_QUALITY, TAG_TEMPLATE, deriveItemSeed, deriveSettlementSeed, deriveStreamSeed,
  makeEquipRng, rollWeightedIndex,
} from './rng.ts';

export interface EquipBaseRow {
  equipId: number; slot: number; mainStat: string; baseValue: number; weight: number;
}

export interface AffixRow {
  affixId: number; group: number; stat: string; rollType: number;
  min: number; max: number; weight: number; qualityMin: number; qualityMax: number;
}

export interface EquipQualityRow {
  qualityId: number; affixMin: number; affixMax: number;
  rareForLuck: boolean; unidentified: boolean; requiredGroups: number[];
}

export interface DropRuleRow {
  dropId: number; source: number;
  weights: number[]; // [白,绿,蓝,紫,橙,红] → qualityId 0..5
  luckApply: boolean; pityQuality: number; pityCount: number; pityUnit: string;
  equipLvMode: string; equipLvOffsetMin: number; equipLvOffsetMax: number;
}

export interface EquipDropConfig {
  rules: Map<number, DropRuleRow>;
  equipBase: EquipBaseRow[];
  affixes: AffixRow[];
  qualities: Map<number, EquipQualityRow>;
}

export interface PityState {
  schemaVersion: number;
  counters: Record<string, number>;
}

export interface DropRequest {
  rootSeed: number;
  settlementSeq: number;
  dropId: number;
  dropCount: number;
  monsterLevel: number;
  luckValue: number;
  pityState: PityState;
}

export interface EquipAffixInst {
  affixId: number; stat: string; rollType: number; valueMicro: number;
}

/** 掉落产物：affixes 仅供演出/对拍展开；持久化只存 EquipInstance 字段（docs/08 M3） */
export interface EquipInstance {
  instanceId: string;
  equipId: number;
  quality: number;
  level: number;
  rollSeed: number;
  identified: boolean;
  affixes: EquipAffixInst[];
}

export interface DropSettlement {
  settlementSeq: number;
  dropId: number;
  items: EquipInstance[];
  pityBefore: PityState;
  pityAfter: PityState;
  pityTriggered: boolean;
  error: string;
  canonicalLog: string[];
}

export interface ResolvedEquipView {
  instanceId: string;
  equipId: number;
  slot: number;
  mainStat: string;
  mainValueMicro: number;
  quality: number;
  level: number;
  identified: boolean;
  affixes: EquipAffixInst[];
}

export function emptyPityState(): PityState {
  return { schemaVersion: 1, counters: {} };
}

/** 幸运值（docs/08 §3）：稀有档（rareForLuck）×(1+luck/1000)，随后整表归一化前的权重 */
export function applyLuck(rule: DropRuleRow, qualities: Map<number, EquipQualityRow>, luck: number): number[] {
  return rule.weights.map((w, q) => {
    if (!rule.luckApply) return w;
    const row = qualities.get(q);
    return row?.rareForLuck ? w * (1 + luck / 1000) : w;
  });
}

function clonePity(state: PityState): PityState {
  return { schemaVersion: state.schemaVersion, counters: { ...state.counters } };
}

/** 词条展开：掉落与鉴定共用同一展开（鉴定幂等的依据） */
function expandAffixes(
  itemSeed: number, quality: number, level: number, ec: EquipDropConfig, g: G,
): EquipAffixInst[] {
  const qRow = ec.qualities.get(quality);
  if (!qRow) throw new Error(`未知品质 ${quality}`);
  const span = qRow.affixMax - qRow.affixMin + 1;
  const countRng = makeEquipRng(deriveStreamSeed(itemSeed, TAG_AFFIX_COUNT));
  const count = qRow.affixMin + rollWeightedIndex(new Array<number>(span).fill(1), countRng);
  if (count <= 0) return [];

  let candidates = ec.affixes.filter(a => quality >= a.qualityMin && quality <= a.qualityMax);
  const selectRng = makeEquipRng(deriveStreamSeed(itemSeed, TAG_AFFIX_SELECT));
  const valueRng = makeEquipRng(deriveStreamSeed(itemSeed, TAG_AFFIX_VALUE));
  const picked: AffixRow[] = [];
  for (let i = 0; i < count; i++) {
    const pool = candidates.filter(a => !picked.some(p => p.stat === a.stat));
    if (pool.length === 0) throw new Error(`品质 ${quality} 需 ${count} 条不同词条，候选不足`);
    const affix = pool[rollWeightedIndex(pool.map(a => a.weight), selectRng)];
    picked.push(affix);
  }
  return picked.map(a => {
    const v = (a.min + valueRng() * (a.max - a.min)) * (1 + level * g.EQUIP_AFFIX_LV_SCALE);
    return { affixId: a.affixId, stat: a.stat, rollType: a.rollType, valueMicro: Math.round(v * 1_000_000) };
  });
}

export function resolveSettlement(req: DropRequest, ec: EquipDropConfig, g: G): DropSettlement {
  const fail = (error: string): DropSettlement => ({
    settlementSeq: req.settlementSeq, dropId: req.dropId, items: [],
    pityBefore: req.pityState, pityAfter: clonePity(req.pityState),
    pityTriggered: false, error, canonicalLog: [],
  });
  const rule = ec.rules.get(req.dropId);
  if (!rule) return fail(`未知 dropId=${req.dropId}`);
  if (!Number.isInteger(req.dropCount) || req.dropCount < 1 || req.dropCount > 99) return fail('dropCount 必须在 1..99');
  if (!Number.isInteger(req.monsterLevel) || req.monsterLevel < 1) return fail('monsterLevel 必须 >= 1');
  if (!(req.luckValue >= 0)) return fail('luckValue 必须 >= 0');

  const settleSeed = deriveSettlementSeed(req.rootSeed, req.settlementSeq, req.dropId);
  const adjusted = applyLuck(rule, ec.qualities, req.luckValue);

  // ① 品质自然 roll（保底覆盖不删除自然结果，流序稳定）
  const qualities: number[] = [];
  for (let i = 0; i < req.dropCount; i++) {
    const itemSeed = deriveItemSeed(settleSeed, i);
    const qr = makeEquipRng(deriveStreamSeed(itemSeed, TAG_QUALITY));
    qualities.push(rollWeightedIndex(adjusted, qr));
  }

  // ② 保底（settlement 语义：一次结算至多推进一格）
  const pityBefore = clonePity(req.pityState);
  const pityAfter = clonePity(req.pityState);
  let pityTriggered = false;
  const counterKey = String(req.dropId);
  if (rule.pityQuality > 0 && rule.pityCount > 0 && rule.pityUnit === 'settlement' && req.dropCount > 0) {
    const before = pityBefore.counters[counterKey] ?? 0;
    if (qualities.some(q => q >= rule.pityQuality)) {
      pityAfter.counters[counterKey] = 0;
    } else if (before + 1 >= rule.pityCount) {
      const pityRng = makeEquipRng(deriveStreamSeed(settleSeed, TAG_PITY_INDEX));
      const forced = rollWeightedIndex(new Array<number>(req.dropCount).fill(1), pityRng);
      qualities[forced] = rule.pityQuality;
      pityAfter.counters[counterKey] = 0;
      pityTriggered = true;
    } else {
      pityAfter.counters[counterKey] = before + 1;
    }
  }

  // ③ 模板 / 等级 / 词条
  const items: EquipInstance[] = [];
  const log: string[] = [];
  log.push(
    `[loot] seed=${req.rootSeed >>> 0} seq=${req.settlementSeq} dropId=${req.dropId} count=${req.dropCount}` +
    ` pityBefore=${pityBefore.counters[counterKey] ?? 0} pityAfter=${pityAfter.counters[counterKey] ?? 0}` +
    ` pityTriggered=${pityTriggered ? 1 : 0}`,
  );
  for (let i = 0; i < req.dropCount; i++) {
    const itemSeed = deriveItemSeed(settleSeed, i);
    const quality = qualities[i];
    const qRow = ec.qualities.get(quality);
    if (!qRow) return fail(`品质 ${quality} 无 EquipQuality 配置`);

    const templateRng = makeEquipRng(deriveStreamSeed(itemSeed, TAG_TEMPLATE));
    const template = ec.equipBase[rollWeightedIndex(ec.equipBase.map(e => e.weight), templateRng)]
      ?? ec.equipBase[ec.equipBase.length - 1];

    if (rule.equipLvMode !== 'monster_level') return fail(`Phase 0 不支持 equipLvMode=${rule.equipLvMode}`);
    const offsetSpan = rule.equipLvOffsetMax - rule.equipLvOffsetMin + 1;
    const levelRng = makeEquipRng(deriveStreamSeed(itemSeed, TAG_LEVEL));
    const offset = rule.equipLvOffsetMin + rollWeightedIndex(new Array<number>(offsetSpan).fill(1), levelRng);
    const level = Math.max(g.EQUIP_LEVEL_MIN, req.monsterLevel + offset);

    const affixes = expandAffixes(itemSeed, quality, level, ec, g);
    items.push({
      instanceId: `${req.settlementSeq}-${i}`,
      equipId: template.equipId, quality, level,
      rollSeed: itemSeed, identified: !qRow.unidentified, affixes,
    });
    log.push(
      `[loot_item] index=${i} instanceId=${req.settlementSeq}-${i} equipId=${template.equipId}` +
      ` quality=${quality} level=${level} identified=${qRow.unidentified ? 0 : 1}` +
      ` rollSeed=${itemSeed >>> 0} affixCount=${affixes.length}`,
    );
    affixes.forEach((a, j) => {
      log.push(`[loot_affix] item=${i} order=${j} affixId=${a.affixId} valueMicro=${a.valueMicro}`);
    });
  }
  log.push(`[loot_end] items=${items.length} applied=0`);
  return {
    settlementSeq: req.settlementSeq, dropId: req.dropId, items,
    pityBefore, pityAfter, pityTriggered, error: '', canonicalLog: log,
  };
}

/** 鉴定：按实例已存 rollSeed 重展开，幂等且不消耗任何正式随机流 */
export function resolveIdentification(inst: EquipInstance, ec: EquipDropConfig, g: G): ResolvedEquipView {
  const template = ec.equipBase.find(e => e.equipId === inst.equipId);
  if (!template) throw new Error(`未知 equipId=${inst.equipId}`);
  const affixes = expandAffixes(inst.rollSeed, inst.quality, inst.level, ec, g);
  const mainValue = template.baseValue * (1 + inst.level * g.EQUIP_MAIN_LV_SCALE);
  return {
    instanceId: inst.instanceId, equipId: inst.equipId, slot: template.slot,
    mainStat: template.mainStat, mainValueMicro: Math.round(mainValue * 1_000_000),
    quality: inst.quality, level: inst.level, identified: inst.identified, affixes,
  };
}
