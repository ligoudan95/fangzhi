/** 经济模拟器（TS 基准）——与 scripts/logic/economy_sim.gd 镜像。docs/18 §3 */
export const PROFILE = { IDLE: 0, NORMAL: 1, ACTIVE: 2 } as const;
export type Profile = 0 | 1 | 2;

interface SeasonConfig { seasons: Map<number, { farmMult: number; mineMult: number }> }

export interface DayLog {
  day: number; season: number; login: number; battle: number;
  harvest: number; mine: number; spend: number; 兽贝余额: number;
}

export function simulate(profile: Profile, days: number, seasonLengthDays: number, config: SeasonConfig): {
  days: number; profile: number; inventory: Record<string, number>; dailyLog: DayLog[];
} {
  const dailyLog: DayLog[] = [];
  const inventory: Record<string, number> = { 灵晶: 0, 兽贝: 0, 铁矿: 0 };
  const loginCount = _loginsPerDay(profile);
  const harvestPerLogin = _harvestPerLogin(profile);
  const battlePerLogin = _battlePerLogin(profile);

  for (let day = 0; day < days; day++) {
    const season = Math.floor(day / seasonLengthDays) % 4;
    const farmMult = _seasonMult(season, config, 'farmMult');
    const mineMult = _seasonMult(season, config, 'mineMult');
    const harvest = Math.floor(harvestPerLogin * loginCount * farmMult);
    const mine = Math.floor(4 * loginCount * mineMult);
    const spend = _dailySpend(profile);
    inventory['兽贝'] += harvest * 20 - spend;
    inventory['铁矿'] += mine;
    dailyLog.push({
      day, season, login: loginCount, battle: battlePerLogin * loginCount,
      harvest, mine, spend, 兽贝余额: inventory['兽贝'],
    });
  }
  return { days, profile, inventory, dailyLog };
}

function _loginsPerDay(p: Profile): number { return p === 0 ? 1 : p === 1 ? 2 : 4; }
function _harvestPerLogin(p: Profile): number { return p === 0 ? 3 : p === 1 ? 4 : 5; }
function _battlePerLogin(p: Profile): number { return p === 0 ? 1 : p === 1 ? 2 : 4; }
function _dailySpend(p: Profile): number { return p === 0 ? 50 : p === 1 ? 100 : 200; }
function _seasonMult(s: number, c: SeasonConfig, key: 'farmMult' | 'mineMult'): number {
  return c.seasons.get(s)?.[key] ?? 1;
}
