/**
 * 属性成长模型（02文档 §3）
 * 最终属性 = (种族基础 + 等级×种族成长×资质/1000) × 突破倍率 × 境界倍率^突破数 × (1+偏移)
 */
export interface Stats { hp: number; atk: number; def: number; spd: number; mag: number; res: number }
export interface Aptitudes { atk: number; def: number; hp: number; spd: number; mag: number }
export interface Offsets { hp: number; atk: number; def: number; spd: number; mag: number; res: number }
export type G = Record<string, number>;

/** 定位模板（02文档 §3.2）：Tpl 1物理 2法术 3坦克 4辅助 */
export const TEMPLATES: Record<number, { name: string; base: Stats; grow: Stats }> = {
  1: { name: 'phys', base: { hp: 500, atk: 55, def: 33, spd: 40, mag: 20, res: 20 }, grow: { hp: 48, atk: 5.2, def: 3.1, spd: 3.0, mag: 1.8, res: 1.8 } },
  2: { name: 'mage', base: { hp: 450, atk: 20, def: 20, spd: 42, mag: 55, res: 26 }, grow: { hp: 42, atk: 1.8, def: 1.9, spd: 3.1, mag: 5.2, res: 2.4 } },
  3: { name: 'tank', base: { hp: 650, atk: 40, def: 45, spd: 32, mag: 18, res: 30 }, grow: { hp: 60, atk: 3.6, def: 4.2, spd: 2.4, mag: 1.6, res: 2.8 } },
  4: { name: 'support', base: { hp: 520, atk: 25, def: 28, spd: 44, mag: 35, res: 28 }, grow: { hp: 48, atk: 2.2, def: 2.6, spd: 3.3, mag: 3.2, res: 2.6 } },
};

/** 突破倍率：按等级取阶段（02文档 §3.3） */
export function breakMult(level: number, g: G): number {
  if (level >= g.BRK_LV5) return g.BRK_M5;
  if (level >= g.BRK_LV4) return g.BRK_M4;
  if (level >= g.BRK_LV3) return g.BRK_M3;
  if (level >= g.BRK_LV2) return g.BRK_M2;
  return 1.0;
}

export function computeStats(tpl: number, off: Offsets, level: number, apt: Aptitudes, realmBreaks: number, g: G): Stats {
  const t = TEMPLATES[tpl];
  const bm = breakMult(level, g) * Math.pow(g.REALM_MULT, realmBreaks);
  const raw: Stats = {
    hp: t.base.hp + level * t.grow.hp * (apt.hp / 1000),
    atk: t.base.atk + level * t.grow.atk * (apt.atk / 1000),
    def: t.base.def + level * t.grow.def * (apt.def / 1000),
    spd: t.base.spd + level * t.grow.spd * (apt.spd / 1000),
    mag: t.base.mag + level * t.grow.mag * (apt.mag / 1000),
    res: t.base.res + level * t.grow.res * (apt.mag / 1000), // 抗性成长随灵力资质（v0简化：资质表仅5维）
  };
  return {
    hp: Math.round(raw.hp * bm * (1 + off.hp)),
    atk: Math.round(raw.atk * bm * (1 + off.atk)),
    def: Math.round(raw.def * bm * (1 + off.def)),
    spd: Math.round(raw.spd * bm * (1 + off.spd)),
    mag: Math.round(raw.mag * bm * (1 + off.mag)),
    res: Math.round(raw.res * bm * (1 + off.res)),
  };
}

/** 战力公式（02文档 §8.1） */
export function powerOf(s: Stats, g: G): number {
  return Math.round(
    s.hp * g.POWER_W_HP + s.atk * g.POWER_W_ATK + s.def * g.POWER_W_DEF +
    s.mag * g.POWER_W_MAG + s.res * g.POWER_W_RES + s.spd * g.POWER_W_SPD,
  );
}
