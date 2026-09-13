/** 战斗引擎类型（03文档） */
import type { Stats } from './stats.ts';

export interface EffectDef {
  type: string; power: number; buffId: number; duration: number; chance: number; hitCount: number; onSelf: boolean;
}

export interface SkillRow {
  skillId: number; name: string; element: number; selector: string;
  effects: EffectDef[]; cd: number; rageGain: number; learnLv: number; isUlt: boolean;
}

export interface PetRow {
  petId: number; name: string; element: number; quality: number; template: number;
  offHp: number; offAtk: number; offDef: number; offSpd: number; offMag: number; offRes: number;
  aptitudes: number[]; laborPow: number; laborDex: number; laborApt: number;
  natures: string[]; breaks: string[]; captureNote: string;
}

export interface BuffRow {
  buffId: number; name: string; kind: number; modStat: string; modPct: number;
  modStat2: string; modPct2: number; dotPct: number; dotElement: number;
  markElement: number; markPct: number; ctrlRes: number; stacks: number;
  duration: number; captureLinked: boolean; control: number;
}

/** 战斗单位输入（由存档/关卡构造） */
export interface PetInput {
  petId: number;
  level: number;
  apts: { atk: number; def: number; hp: number; spd: number; mag: number };
  realmBreaks: number;          // 已突破的大境数（境界全局倍率指数）
  skillIds: number[];           // [普攻, 主动1, 主动2, 绝技]
  captureable?: boolean;        // 野生可捕捉
  strategy?: string;            // 敌方AI标签
  isEnemy?: boolean;
  natureMods?: Record<string, number>;  // 性格修正（并入种族偏移，docs/04 §3）
  statMods?: Record<string, number>;    // 装备平面加成（docs/08 §4/§5，compute 后叠加）
}

export interface BuffInst { def: BuffRow; stacks: number; remain: number }

export interface Unit {
  uid: number; side: 0 | 1; petId: number; name: string; element: number; level: number;
  stats: Stats; hp: number; shield: number; rage: number;
  skills: SkillRow[]; cds: number[];
  buffs: BuffInst[];
  alive: boolean; captureable: boolean; strategy: string;
  ctrlHistory: number[];       // 最近回合被控标记（控制递减窗口）
  tauntTarget: number | -1;    // 嘲讽指向的uid，-1无
  tauntRemain: number;         // 嘲讽剩余回合
  capBonus: number;            // 本回合捕捉率加成（地听等）
}

export type BattleOutcome = 'victory' | 'defeat' | 'captured' | 'timeout';

export interface BattleResult {
  outcome: BattleOutcome;
  rounds: number;
  log: string[];
  /** 结构化事件（docs/10 §8.1）：View 演出数据源；与日志同点发射、不消耗 RNG */
  events: Array<Record<string, unknown>>;
  capturedPetId?: number;
}
