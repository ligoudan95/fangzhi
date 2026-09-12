/**
 * 村落生产结算（TS 基准，docs/15 §2 / docs/26 §3）——纯函数：
 * settle(fields, cursor, now, config) 按时间切片套季节系数，成熟田块一次性收获后清空；
 * 不原地改输入，返回 {nextFields, outputs, nextCursor, inventory}。幂等：同输入同输出。
 */
import { addItem, applyOverflowDecay, type ItemStack } from './inventoryLedger.ts';
import { sliceRange, seasonOfYear } from './timeSlicer.ts';

export interface CropRow {
  cropId: number; growMin: number; yieldN: number;
  outputItemId: number; outputCount: number;
}

export interface FieldState { slotId: number; cropId: number; startedAtUtcSec: number }

export interface VillageConfig {
  crops: Map<number, CropRow>;
  seasons: Map<number, { farmMult: number }>;
  categoryOf: Map<number, number>;          // itemId → storageCategory
  storageRules: Map<number, number>;        // categoryId → baseCap
  g: {
    SEASON_EPOCH_UTC_SEC: number; OFFLINE_CAP_BASE_SEC: number;
    STORAGE_DECAY_PCT: number; STORAGE_DECAY_PERIOD_SEC: number;
  };
}

export interface SettleOutput { itemId: number; amount: number; season: number }

export interface SettleResult {
  nextFields: FieldState[];
  nextCursor: number;
  outputs: SettleOutput[];
  cappedBy: number;         // 结算窗口被离线上限截断的秒数（0=未截断）
  inventory: ItemStack[];
}

/**
 * 结算窗口 [cursor, min(now, cursor+cap))（docs/15 §2.1/§2.2）。
 * 田块成熟：startedAt + growMin*60 落在某切片 (start, end] 内 → 按该切片季节系数产出，
 * 并从 nextFields 移除（收获后清空；重播属玩家操作，Phase A 无自动重播）。
 * 溢出衰减：窗口内每满 STORAGE_DECAY_PERIOD_SEC 对超软上限分类扣 STORAGE_DECAY_PCT（§2.4）。
 */
export function settleCrops(
  fields: FieldState[], cursor: number, now: number, inventory: ItemStack[], config: VillageConfig,
): SettleResult {
  if (now <= cursor) {
    return { nextFields: fields.map(f => ({ ...f })), nextCursor: cursor, outputs: [], cappedBy: 0, inventory: inventory.map(s => ({ ...s })) };
  }
  const cappedNow = Math.min(now, cursor + config.g.OFFLINE_CAP_BASE_SEC);
  const cappedBy = now - cappedNow;
  const slices = sliceRange(cursor, cappedNow, config.g.SEASON_EPOCH_UTC_SEC);
  const outputs: SettleOutput[] = [];
  const harvested = new Set<number>();
  let inv = inventory.map(s => ({ ...s }));
  for (const slice of slices) {
    const season = seasonOfYear(slice.start, config.g.SEASON_EPOCH_UTC_SEC);
    const farmMult = config.seasons.get(season)?.farmMult ?? 1;
    for (const field of fields) {
      if (harvested.has(field.slotId)) continue;
      const crop = config.crops.get(field.cropId);
      if (!crop) continue;
      const matureAt = field.startedAtUtcSec + crop.growMin * 60;
      if (matureAt <= slice.start || matureAt > slice.end) continue;
      const amount = Math.round(crop.outputCount * farmMult);
      if (amount > 0) {
        const res = addItem(inv, crop.outputItemId, amount, config.categoryOf, config.storageRules);
        inv = res.stacks;
        outputs.push({ itemId: crop.outputItemId, amount, season });
      }
      harvested.add(field.slotId);
    }
  }
  const nextFields = fields.filter(f => !harvested.has(f.slotId)).map(f => ({ ...f }));
  const periods = Math.floor((cappedNow - cursor) / config.g.STORAGE_DECAY_PERIOD_SEC);
  if (periods > 0) {
    for (const [category, cap] of config.storageRules) {
      const items = [...config.categoryOf.entries()].filter(([, c]) => c === category).map(([id]) => id);
      const decayed = applyOverflowDecay(inv, items, cap, periods, config.g.STORAGE_DECAY_PCT);
      inv = decayed.stacks;
    }
  }
  return { nextFields, nextCursor: now, outputs, cappedBy, inventory: inv };
}
