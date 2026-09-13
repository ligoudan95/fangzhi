/**
 * 配方生产（TS 基准）——与 scripts/logic/recipe_craft.gd 逐位一致（docs/05 §7 / docs/26 §4.2）。
 * 纯函数：inputs 解析 → 队列容量校验 → 扣料入队 → 到时结算产出。
 */

import { addItem, type ItemStack } from './inventoryLedger.ts';

export interface CraftJob { recipeId: number; startedAtUtcSec: number }
export interface RecipeRow {
  recipeId: number; station: number; inputs: string;
  outputItemId: number; outputCount: number; durationMin: number;
}

export interface InputPair { itemId: number; count: number }

/** 解析 "itemId:count;itemId:count"；非法段跳过 */
export function parseInputs(raw: string): InputPair[] {
  const out: InputPair[] = [];
  for (const seg of raw.split(';')) {
    if (!seg) continue;
    const pair = seg.split(':');
    if (pair.length !== 2) continue;
    const itemId = Number(pair[0]);
    const count = Number(pair[1]);
    if (itemId > 0 && count > 0) out.push({ itemId, count });
  }
  return out;
}

/** 开始生产：队列未满 + 库存足料 → 扣料入队；返回 {error, jobs, inventory}（不修改输入） */
export function startCraft(
  jobs: CraftJob[], recipeId: number, inputsRaw: string, now: number,
  inventory: ItemStack[], queueCap: number,
): { error: string; jobs: CraftJob[]; inventory: ItemStack[] } {
  const nextJobs = jobs.map(j => ({ ...j }));
  if (nextJobs.length >= queueCap) {
    return { error: '队列已满', jobs: nextJobs, inventory: inventory.map(s => ({ ...s })) };
  }
  let inv = inventory.map(s => ({ ...s }));
  const needs = parseInputs(inputsRaw);
  for (const need of needs) {
    const have = inv.find(s => s.itemId === need.itemId)?.amount ?? 0;
    if (have < need.count) return { error: '材料不足', jobs: nextJobs, inventory: inv };
  }
  for (const need of needs) {
    const s = inv.find(x => x.itemId === need.itemId);
    if (s) s.amount -= need.count;
  }
  inv = inv.filter(s => s.amount > 0);
  nextJobs.push({ recipeId, startedAtUtcSec: now });
  return { error: '', jobs: nextJobs, inventory: inv };
}

/** 结算：到时任务（elapsed ≥ durationMin×60）产出入库；未到期保留 */
export function settleCrafts(
  jobs: CraftJob[], now: number, inventory: ItemStack[],
  recipeOf: (recipeId: number) => RecipeRow | undefined,
  categoryOf: Map<number, number>, rules: Map<number, number>, capMult: number,
): { nextJobs: CraftJob[]; outputs: { itemId: number; amount: number }[]; inventory: ItemStack[] } {
  let inv = inventory.map(s => ({ ...s }));
  const nextJobs: CraftJob[] = [];
  const outputs: { itemId: number; amount: number }[] = [];
  for (const j of jobs) {
    const row = recipeOf(j.recipeId);
    if (!row) continue;
    const durationSec = row.durationMin * 60;
    if (now - j.startedAtUtcSec < durationSec) {
      nextJobs.push({ ...j });
      continue;
    }
    if (row.outputItemId > 0 && row.outputCount > 0) {
      try {
        const res = addItem(inv, row.outputItemId, row.outputCount, categoryOf, rules, capMult);
        inv = res.stacks;
        outputs.push({ itemId: row.outputItemId, amount: row.outputCount });
      } catch {
        // 无分类/规则的产物跳过（GD 侧同口径：error 非空不入 outputs）
      }
    }
  }
  return { nextJobs, outputs, inventory: inv };
}
