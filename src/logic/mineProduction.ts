/**
 * 矿场结算（TS 基准）——与 scripts/logic/mine_production.gd 逐行镜像（docs/26 §4.3 / docs/05 §6）。
 * 纯函数：切片×季节系数，小时折算产量；物品入软容量库存，灵晶进钱包。
 */
import { addItem, type ItemStack } from './inventoryLedger.ts';
import { sliceRange, seasonOfYear } from './timeSlicer.ts';

export interface MineJob { slotId: number; mineId: number; startedAtUtcSec: number; assignedPetInstanceIds: number[] }
export interface MineRow { mineId: number; ironRate: number; crystalRate: number; refinedRate: number; spiritRate: number }

export interface MineConfig {
  mines: Map<number, MineRow>;
  seasons: Map<number, { mineMult: number }>;
  categoryOf: Map<number, number>;
  storageRules: Map<number, number>;
  g: { SEASON_EPOCH_UTC_SEC: number; OFFLINE_CAP_BASE_SEC: number };
}

export interface MineOutput { itemId: number; amount: number }

export function settleMines(
  jobs: MineJob[], cursor: number, now: number,
  wallet: { beastShell: number; spiritCrystal: number; totemEmblem: number },
  inventory: ItemStack[], config: MineConfig,
): { nextCursor: number; wallet: typeof wallet; inventory: ItemStack[]; outputs: MineOutput[] } {
  if (now <= cursor) {
    return { nextCursor: cursor, wallet: { ...wallet }, inventory: inventory.map(s => ({ ...s })), outputs: [] };
  }
  const cappedNow = Math.min(now, cursor + config.g.OFFLINE_CAP_BASE_SEC);
  const slices = sliceRange(cursor, cappedNow, config.g.SEASON_EPOCH_UTC_SEC);
  let inv = inventory.map(s => ({ ...s }));
  const wal = { ...wallet };
  const outputs: MineOutput[] = [];
  // 分数产出跨切片结转：300s 切片内 rate×hours 常小于 1，逐片 floor 会清零——用余数累积
  const pending = new Map<string, number>();
  for (const slice of slices) {
    const season = seasonOfYear(slice.start, config.g.SEASON_EPOCH_UTC_SEC);
    const mult = config.seasons.get(season)?.mineMult ?? 1;
    const hours = (slice.end - slice.start) / 3600;
    for (const job of jobs) {
      const mine = config.mines.get(job.mineId);
      if (!mine) continue;
      // 派遣效率（docs/05 §4）：绑宠作业由会话注入快照倍率；默认 1（对拍兼容）
      const eff = (job as { efficiency?: number }).efficiency ?? 1;
      const produce = (key: string, itemId: number, rate: number, toWallet: boolean) => {
        if (rate <= 0) return;
        const exact = (pending.get(key) ?? 0) + rate * mult * hours;
        const amount = Math.floor(exact + 1e-9);  // 浮点累积误差容差
        pending.set(key, exact - amount);
        if (amount <= 0) return;
        if (toWallet) {
          wal.spiritCrystal += amount;
          outputs.push({ itemId: -1, amount });
          return;
        }
        if (itemId <= 0) return;
        const res = addItem(inv, itemId, amount, config.categoryOf, config.storageRules);
        inv = res.stacks;
        outputs.push({ itemId, amount });
      };
      produce(`${job.slotId}:iron`, 201, Math.round(mine.ironRate * eff), false);
      produce(`${job.slotId}:crystal`, 202, Math.round(mine.crystalRate * eff), false);
      produce(`${job.slotId}:refined`, 203, Math.round(mine.refinedRate * eff), false);
      produce(`${job.slotId}:spirit`, -1, Math.round(mine.spiritRate * eff), true);
    }
  }
  return { nextCursor: now, wallet: wal, inventory: inv, outputs };
}
