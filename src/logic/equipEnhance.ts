/** 装备强化与套装效果（TS 基准）——与 scripts/logic/equip_enhance.gd 镜像 */
export function enhanceCost(currentLevel: number): { metalIngot: number; spiritCrystal: number } {
  return {
    metalIngot: currentLevel + 1,
    spiritCrystal: Math.round(500 * Math.pow(1.3, currentLevel)),
  };
}

export function enhanceSuccessRate(currentLevel: number): number {
  if (currentLevel < 3) return 1.0;
  if (currentLevel < 7) return 0.95;
  if (currentLevel < 10) return 0.85;
  if (currentLevel < 13) return 0.70;
  return 0.50;
}

export function maxEnhanceLevel(forgeLevel: number): number {
  return Math.min(15, forgeLevel * 3);
}

export function activeSetBonus(equippedSetIds: number[]): Map<number, { pieces: number; tier: number }> {
  const counts = new Map<number, number>();
  for (const sid of equippedSetIds) counts.set(sid, (counts.get(sid) ?? 0) + 1);
  const active = new Map<number, { pieces: number; tier: number }>();
  for (const [sid, n] of counts) {
    if (n >= 2) active.set(sid, { pieces: n, tier: n >= 3 ? 3 : 2 });
  }
  return active;
}

export function enhanceMultiplier(enhanceLevel: number): number {
  return 1.0 + enhanceLevel * 0.05;
}
