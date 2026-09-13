/**
 * 穿戴装备 → 属性修正管线（TS 基准）——与 scripts/logic/equip_stats.gd 逐位一致
 * （docs/08 §4/§5/§7）。主属性+词条（rollType 1 百分比/2 平面）×强化倍率；
 * 套装 2/3 件——六维键进 ratio，特殊机制键只列出（战斗消费待引擎扩展）。
 */
import {
  resolveIdentification,
  type EquipDropConfig,
  type EquipInstance,
  type ResolvedEquipView,
} from '../equipment/drop.ts';
import { activeSetBonus, enhanceMultiplier } from './equipEnhance.ts';

/** 鉴定视图字段与 GD 侧一致（error 以异常表达，捕获后跳过——与 GD 静默跳过同口径） */
type EquipInstanceWithEnhance = EquipInstance & { identified: boolean; enhanceLevel?: number };

function tryResolve(
  item: EquipInstanceWithEnhance, ec: EquipDropConfig, g: Record<string, number>,
): ResolvedEquipView | null {
  try {
    return resolveIdentification(item, ec, g);
  } catch {
    return null;
  }
}

export interface EquipSetRow {
  equipSetId: number; name: string;
  bonus2Stat: string; bonus2Pct: number; bonus2Desc: string;
  bonus3Stat: string; bonus3Pct: number; bonus3Desc: string;
}

export interface EquipMods {
  flat: Record<string, number>;
  ratio: Record<string, number>;
  activeSets: { id: number; name: string; tier: number }[];
  special: string[];
}

const BASIC_STATS = ['hp', 'atk', 'def', 'spd', 'mag', 'res'];

/** 穿戴修正：pet.equips 为 {slot: instanceId}；flat 走引擎 statMods，ratio 并入 natureMods */
export function equippedMods(
  pet: { equips?: Record<string, string> }, items: EquipInstanceWithEnhance[],
  ec: EquipDropConfig, setRows: EquipSetRow[], g: Record<string, number>,
): EquipMods {
  const flat: Record<string, number> = {};
  const ratio: Record<string, number> = {};
  const activeSets: EquipMods['activeSets'] = [];
  const special: string[] = [];
  const wornSetIds: number[] = [];
  const equips = pet.equips ?? {};
  for (const instanceId of Object.values(equips)) {
    const item = items.find(it => String(it.instanceId) === instanceId);
    if (!item || !item.identified) continue;
    const view = tryResolve(item, ec, g);
    if (!view) continue;
    const mult = enhanceMultiplier(item.enhanceLevel ?? 0);
    flat[view.mainStat] = (flat[view.mainStat] ?? 0) + Math.round(view.mainValueMicro / 1e6 * mult);
    for (const affix of view.affixes) {
      const value = affix.valueMicro / 1e6 * mult;
      if (affix.rollType === 2) {
        flat[affix.stat] = (flat[affix.stat] ?? 0) + Math.round(value);
      } else {
        ratio[affix.stat] = (ratio[affix.stat] ?? 0) + value;
      }
    }
    const base = ec.equipBase.find(e => e.equipId === item.equipId);
    if (base) wornSetIds.push(base.setId);
  }
  const active = activeSetBonus(wornSetIds);
  for (const [sidStr, info] of active) {
    const sid = Number(sidStr);
    const row = setRows.find(s => s.equipSetId === sid);
    if (!row) continue;
    const tier = info.tier;
    activeSets.push({ id: sid, name: row.name, tier });
    // 3 件 = 2 件 + 3 件效果叠加（docs/08 §7）
    for (const tierI of [2, 3]) {
      if (tier < tierI) continue;
      const stat = tierI === 2 ? row.bonus2Stat : row.bonus3Stat;
      const pct = tierI === 2 ? row.bonus2Pct : row.bonus3Pct;
      const desc = tierI === 2 ? row.bonus2Desc : row.bonus3Desc;
      if ((BASIC_STATS as string[]).includes(stat)) {
        ratio[stat] = (ratio[stat] ?? 0) + pct;
      } else {
        // 特殊机制键（dmg_first/cd_reduce 等）战斗消费待引擎扩展，先登记
        special.push(`${row.name}(${tierI}件)：${desc}`);
      }
    }
  }
  return { flat, ratio, activeSets, special };
}
