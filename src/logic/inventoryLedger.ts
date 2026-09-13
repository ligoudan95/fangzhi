/**
 * 库存账本（TS 基准，docs/15 §2.4 / docs/26 §3）——纯函数，确定性红线：
 * 衰减先按数量比例 floor 分摊、余数按 itemId 升序补齐，TS/GD 逐位一致。
 */

export interface ItemStack { itemId: number; amount: number }

export interface AddResult { added: number; stored: number; cap: number; overflow: number }

/** 软容量入库：可超上限保留；capMult 为仓库建筑倍率（默认 1.0）；不修改输入，返回新数组（按 itemId 升序） */
export function addItem(
  stacks: ItemStack[], itemId: number, amount: number,
  categoryOf: Map<number, number>, rules: Map<number, number>, capMult = 1.0,
): { stacks: ItemStack[]; result: AddResult } {
  if (amount < 0) throw new Error('amount 不能为负');
  const category = categoryOf.get(itemId);
  if (category === undefined) throw new Error(`物品 ${itemId} 无仓储分类`);
  const capBase = rules.get(category);
  if (capBase === undefined) throw new Error(`仓储分类 ${category} 无容量规则`);
  const cap = Math.floor(capBase * capMult);
  const next = stacks.map(s => ({ ...s }));
  const existing = next.find(s => s.itemId === itemId);
  const before = existing ? existing.amount : 0;
  if (existing) existing.amount = before + amount;
  else next.push({ itemId, amount });
  next.sort((a, b) => a.itemId - b.itemId);
  const stored = before + amount;
  return {
    stacks: next,
    result: { added: amount, stored, cap, overflow: Math.max(0, stored - cap) },
  };
}

/** 周期复合后的剩余超额：每周期对当前超额扣 pct（不足 1 按 1 计） */
function remainingOverflow(total: number, cap: number, periods: number, pct: number): number {
  let target = total - cap;
  for (let i = 0; i < periods && target > 0; i++) {
    const step = Math.floor(target * pct);
    target -= step > 0 ? step : 1;
  }
  return Math.max(0, target);
}

/**
 * 溢出衰减（docs/15 §2.4）：仅当分类总量超软上限时，对超额部分按周期复合扣减；
 * 分摊：每堆 floor(堆量/总量 × 衰减量)，余数按 itemId 升序补齐（不超过堆量）。
 */
export function applyOverflowDecay(
  stacks: ItemStack[], categoryItems: number[], cap: number, periods: number, pct: number,
): { stacks: ItemStack[]; decayed: number } {
  const next = stacks.map(s => ({ ...s }));
  const cat = next
    .filter(s => categoryItems.includes(s.itemId))
    .sort((a, b) => a.itemId - b.itemId);
  const total = cat.reduce((a, s) => a + s.amount, 0);
  if (periods <= 0 || pct <= 0 || total <= cap) {
    return { stacks: next, decayed: 0 };
  }
  const decayTotal = Math.min((total - cap) - remainingOverflow(total, cap, periods, pct), total);
  let assigned = 0;
  const floors = cat.map(s => {
    const f = Math.floor((s.amount / total) * decayTotal);
    assigned += f;
    return f;
  });
  let remainder = decayTotal - assigned;
  for (let i = 0; i < cat.length && remainder > 0; i++) {
    const canTake = Math.min(remainder, cat[i].amount - floors[i]);
    floors[i] += canTake;
    remainder -= canTake;
  }
  for (let i = 0; i < cat.length; i++) cat[i].amount -= floors[i];
  return { stacks: next.filter(s => s.amount > 0), decayed: decayTotal };
}
