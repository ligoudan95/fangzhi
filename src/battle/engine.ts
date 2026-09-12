/**
 * 确定性回合制战斗引擎（03文档，headless 可脱离渲染运行）
 * - 全随机走种子 RNG，同种子同输入必同结果（07文档 §5）
 * - 伤害管线/状态效果/控制递减/怒气绝技/替补/捕捉 全量实现
 */
import type { G } from './stats.ts';
import { computeStats } from './stats.ts';
import type { BattleOutcome, BattleResult, BuffInst, BuffRow, EffectDef, PetInput, PetRow, SkillRow, Unit } from './types.ts';
import type { Stats } from './stats.ts';

export interface BattleConfig {
  g: G;
  pets: Map<number, PetRow>;
  skills: Map<number, SkillRow>;
  buffs: Map<number, BuffRow>;
  skillPool: Map<number, SkillPoolEntry[]>; // petId → 按槽位排列的技能及习得等级
}

export interface SkillPoolEntry {
  skillId: number;
  learnLv: number;
}

/** mulberry32 种子随机 */
export function makeRng(seed: number): () => number {
  let a = seed >>> 0;
  return function next(): number {
    a += 0x6D2B79F5;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 五行循环相克：金克木 木克土 土克水 水克火 火克金（02文档 §4.3）
const BEATS: Record<number, number> = { 1: 2, 2: 5, 5: 3, 3: 4, 4: 1 };

export function clash(a: number, d: number, g: G): number {
  if (BEATS[a] === d) return g.CLASH_ADV;
  if (BEATS[d] === a) return g.CLASH_DIS;
  if ((a === 6 && d === 7) || (a === 7 && d === 6)) return g.CLASH_ADV; // 阴阳互克
  return 1;
}

// ---------- 纯伤害计算（可单测） ----------
export interface DamageRoll { hit: boolean; crit: boolean; float: number }
export interface DamageInput {
  atkStat: number; power: number; isPhys: boolean;
  attackerElement: number; defenderElement: number; skillElement: number;
  defStat: number; defenderLevel: number; dmgMod: number; markPct: number;
}
export function calcDamage(inp: DamageInput, roll: DamageRoll, g: G): number {
  if (!roll.hit) return 0;
  const cl = clash(inp.attackerElement, inp.defenderElement, g);
  const mit = Math.min(inp.defStat / (inp.defStat + g.DEF_K * inp.defenderLevel), g.MIT_CAP);
  let d = inp.atkStat * inp.power * cl * (1 - mit);
  if (roll.crit) d *= g.CRIT_DMG;
  d *= inp.dmgMod * (1 + inp.markPct) * roll.float;
  return Math.max(1, Math.round(d));
}

// ---------- 捕捉率（02文档 §5，纯函数可蒙特卡洛） ----------
export interface CaptureInput {
  gourdBase: number; qualityCoef: number; hpPct: number;
  hasControl: boolean; hasCaptureDebuff: boolean; lvlDiff: number; capBonus: number;
}
export function computeCaptureRate(inp: CaptureInput, g: G): number {
  const hp = inp.hpPct > 0.5 ? g.CAP_HP_HI : inp.hpPct > 0.2 ? g.CAP_HP_MID : g.CAP_HP_LO;
  const st = inp.hasControl ? g.CAP_ST_CTRL : inp.hasCaptureDebuff ? g.CAP_ST_DEBUFF : 1;
  const pen = inp.lvlDiff > 0 ? 1 - g.CAP_LVL_PEN * Math.min(inp.lvlDiff, g.CAP_LVL_CAP) : 1;
  return Math.min(1, inp.gourdBase * inp.qualityCoef * hp * st * Math.max(0, pen) * (1 + inp.capBonus));
}

// ---------- 战斗 ----------
export class Battle {
  cfg: BattleConfig;
  g: G;
  rng: () => number;
  units: Unit[] = [];
  bench: Unit[][] = [[], []];
  round = 0;
  log: string[] = [];
  events: Record<string, unknown>[] = [];
  outcome?: BattleOutcome;
  capturedPetId?: number;
  captureMode = false;
  captureTargetUid = -1;
  private pendingCaptureActorUid = -1;
  private uidSeq = 1;

  constructor(cfg: BattleConfig, sideA: PetInput[], sideB: PetInput[], seed: number, opts?: { capture?: boolean }) {
    this.cfg = cfg; this.g = cfg.g; this.rng = makeRng(seed);
    if (opts?.capture) this.captureMode = true;
    for (const p of sideA.slice(0, 3)) this.units.push(this.makeUnit(p, 0));
    for (const p of sideA.slice(3)) this.bench[0].push(this.makeUnit(p, 0));
    for (const p of sideB.slice(0, 3)) this.units.push(this.makeUnit(p, 1));
    for (const p of sideB.slice(3)) this.bench[1].push(this.makeUnit(p, 1));
    if (this.captureMode) {
      const t = this.units.find(u => u.side === 1 && u.captureable);
      if (t) this.captureTargetUid = t.uid;
    }
  }

  private makeUnit(p: PetInput, side: 0 | 1): Unit {
    const pet = this.cfg.pets.get(p.petId)!;
    const skills = p.skillIds
      .map(id => this.cfg.skills.get(id))
      .filter((skill): skill is SkillRow => !!skill && skill.learnLv <= p.level);
    const stats = computeStats(pet.template,
      { hp: pet.offHp, atk: pet.offAtk, def: pet.offDef, spd: pet.offSpd, mag: pet.offMag, res: pet.offRes },
      p.level, p.apts, p.realmBreaks, this.g);
    return {
      uid: this.uidSeq++, side, petId: p.petId, name: pet.name, element: pet.element, level: p.level,
      stats, hp: stats.hp, shield: 0, rage: 0,
      skills, cds: skills.map(() => 0),
      buffs: [], alive: true, captureable: !!p.captureable,
      strategy: p.strategy ?? 'random', ctrlHistory: [], tauntTarget: -1, tauntRemain: 0, capBonus: 0,
    };
  }

  private eff(u: Unit): Stats & { dmg: number } {
    const mod = (k: string) => u.buffs.reduce((a, b) =>
      a + (b.def.modStat === k ? b.def.modPct * b.stacks : 0) + (b.def.modStat2 === k ? b.def.modPct2 * b.stacks : 0), 0);
    const s = u.stats;
    return {
      hp: s.hp, atk: s.atk * (1 + mod('atk')), def: s.def * (1 + mod('def')),
      spd: s.spd * (1 + mod('spd')), mag: s.mag * (1 + mod('mag')), res: s.res * (1 + mod('res')),
      dmg: 1 + mod('dmg'),
    };
  }

  private hasControl(u: Unit): boolean { return u.buffs.some(b => b.def.kind === 2); }
  private controlOf(u: Unit, type: number): boolean { return u.buffs.some(b => b.def.control === type); }
  private enemiesOf(u: Unit): Unit[] { return this.units.filter(x => x.side !== u.side && x.alive); }
  private alliesOf(u: Unit): Unit[] { return this.units.filter(x => x.side === u.side && x.alive); }

  run(): BattleResult {
    this.ev({
      t: 'start', units: this.units.map(u => ({
        u: u.uid, s: u.side, n: u.name, hp: u.stats.hp, el: u.element,
      })),
    });
    for (this.round = 1; this.round <= this.g.ROUND_CAP; this.round++) {
      this.ev({ t: 'round', r: this.round });
      const order = this.units.filter(u => u.alive)
        .map(u => ({ u, r: this.rng() }))
        .sort((a, b) => this.eff(b.u).spd - this.eff(a.u).spd || a.r - b.r);
      for (const { u } of order) {
        if (!u.alive || this.outcome) break;
        this.takeTurn(u);
        if (u.side === 1 && this.pendingCaptureActorUid > 0 && !this.outcome) {
          this.settlePendingCapture();
        }
      }
      this.roundEnd();
      if (this.outcome) break;
      if (!this.enemiesOf({ side: 0 } as Unit).length) { this.outcome = 'victory'; }
      else if (!this.alliesOf({ side: 0 } as Unit).length) { this.outcome = 'defeat'; }
    }
    if (!this.outcome) this.outcome = 'timeout'; // 03§1：回合上限判进攻方负（守方优势）
    this.log.push(`== 战斗结束：${this.outcomeText()}`);
    this.ev({ t: 'end', o: this.outcome, r: this.round });
    return { outcome: this.outcome, rounds: this.round, log: this.log, events: this.events, capturedPetId: this.capturedPetId };
  }

  /** 结构化事件（docs/10 §8.1）：只记录已发生事实，不消耗 RNG；与日志同点发射 */
  private ev(e: Record<string, unknown>): void {
    this.events.push(e);
  }

  private outcomeText(): string {
    switch (this.outcome) {
      case 'victory': return '胜利';
      case 'defeat': return '失败';
      case 'captured': return `捕捉成功（${this.capturedPetId}号灵宠入队）`;
      default: return '超时判负';
    }
  }

  /** 日志显示名：敌方加前缀，便于同名灵宠区分 */
  private n(u: Unit): string {
    return u.side === 1 ? `[敌]${u.name}` : u.name;
  }

  private takeTurn(u: Unit) {
    if (this.controlOf(u, 1) || this.controlOf(u, 2) || this.controlOf(u, 3)) { // 冰冻/眩晕/催眠跳过
      this.log.push(`R${this.round} ${this.n(u)} 被控制无法行动`);
      return;
    }
    if (this.controlOf(u, 4) && this.rng() < 0.5) { // 麻痹50%
      this.log.push(`R${this.round} ${this.n(u)} 麻痹无法行动`);
      return;
    }
    if (u.side === 0 && this.shouldPrepareCapture()) {
      this.pendingCaptureActorUid = u.uid;
      this.log.push(`R${this.round} ${this.n(u)} 准备收妖`);
      return;
    }
    const act = this.chooseAction(u);
    if (!act) return;
    const [skill, targets] = act;
    u.cds[u.skills.indexOf(skill)] = skill.cd;
    this.log.push(`R${this.round} ${this.n(u)} 施放【${skill.name}】`);
    this.ev({ t: 'cast', r: this.round, u: u.uid, s: skill.name, tg: targets.map(t0 => t0.uid) });
    for (const e of skill.effects) this.applyEffect(u, skill, e, targets);
    // 怒气：普攻命中+30（rageGain），受击在 applyDamage 中结算
    if (skill.rageGain > 0) u.rage = Math.min(this.g.RAGE_MAX, u.rage + skill.rageGain);
  }

  /** 捕捉模式在最优血线内由首个可行动单位消耗行动准备收妖。 */
  private shouldPrepareCapture(): boolean {
    if (!this.captureMode || this.pendingCaptureActorUid > 0) return false;
    const target = this.units.find(x => x.uid === this.captureTargetUid && x.alive);
    return !!target && target.hp / target.stats.hp < 0.2;
  }

  private settlePendingCapture(): void {
    const actorUid = this.pendingCaptureActorUid;
    this.pendingCaptureActorUid = -1;
    const target = this.units.find(u => u.uid === this.captureTargetUid && u.alive);
    if (!target) return;
    const qualityCoef = Number(this.g[`CAP_Q${this.cfg.pets.get(target.petId)!.quality}` as keyof G]);
    this.tryCapture(actorUid, this.g.CAP_GOURD_JADE, qualityCoef);
  }

  /** AI 决策（03文档 §7） */
  private chooseAction(u: Unit): [SkillRow, Unit[]] | null {
    const sealed = this.controlOf(u, 5);
    const ult = u.skills[3];
    const basic = u.skills[0];
    const actives = [u.skills[1], u.skills[2]];
    const ready = (s?: SkillRow) => !!s && u.cds[u.skills.indexOf(s)] <= 0;
    const enemyTargets = this.pickTargets(u);

    // 绝技优先（封技除外）
    if (!sealed && ult && u.rage >= this.g.RAGE_MAX && ready(ult)) {
      u.rage = 0;
      return [ult, this.selectTargets(u, ult, enemyTargets)];
    }
    // 我方AI：治疗优先（队友<35%）
    if (u.side === 0) {
      for (const s of actives) {
        if (ready(s) && s.effects.some(e => e.type === 'Heal')) {
          const low = this.alliesOf(u).filter(a => a.hp / a.stats.hp < 0.35);
          if (low.length) return [s, this.selectTargets(u, s, low)];
        }
      }
      // 捕捉模式：优先控制捕捉目标（03§10）
      if (this.captureMode && this.captureTargetUid > 0) {
        const t = this.units.find(x => x.uid === this.captureTargetUid && x.alive);
        if (t && !this.hasControl(t)) {
          for (const s of actives) {
            if (ready(s) && s.effects.some(e => e.type === 'ApplyBuff' && (this.cfg.buffs.get(e.buffId)?.kind === 2))) {
              return [s, [t]];
            }
          }
        }
      }
    }
    // 敌方AI：策略选目标（03§7.2）
    if (!enemyTargets.length) return null;
    const pickByStrategy = (): Unit => {
      const es = enemyTargets;
      switch (u.strategy) {
        case 'focus_weak': return es.reduce((a, b) => a.hp / a.stats.hp <= b.hp / b.stats.hp ? a : b);
        case 'focus_squishy': return es.reduce((a, b) => this.eff(a).def <= this.eff(b).def ? a : b);
        case 'caster_first': return es.reduce((a, b) => this.eff(a).mag >= this.eff(b).mag ? a : b);
        default: return es[Math.floor(this.rng() * es.length)] ?? es[0];
      }
    };
    // 可用主动技按期望伤害选（我方附加击杀检测）
    let best: [SkillRow, Unit[]] | null = null;
    let bestScore = -1;
    for (const s of actives) {
      if (!ready(s)) continue;
      const dmgE = s.effects.find(e => e.type === 'PhysDamage' || e.type === 'MagDamage');
      if (!dmgE) continue; // 非伤害技已在前文处理
      for (const t of enemyTargets) {
        const te = this.eff(t), ue = this.eff(u);
        const score = (ue.atk > ue.mag ? ue.atk : ue.mag) * dmgE.power *
          clash(u.element, t.element, this.g) * (1 + dmgE.hitCount - 1) * (t.hp < 999999 ? 1 : 1);
        const kill = dmgE.power * (ue.atk > ue.mag ? ue.atk : ue.mag) >= t.hp ? 2 : 1; // 击杀加权
        const v = score * kill;
        if (v > bestScore) { bestScore = v; best = [s, s.selector === 'enemy_all' || s.selector === 'ally_all' ? enemyTargets : [t]]; }
      }
    }
    if (best && this.rng() > 0.2) return best; // 20%概率退化用普攻（行为多样性）
    return [basic, [pickByStrategy()]];
  }

  /** 嘲讽覆盖目标选择 */
  private pickTargets(u: Unit): Unit[] {
    const es = this.enemiesOf(u);
    if (u.tauntTarget > 0) {
      const t = this.units.find(x => x.uid === u.tauntTarget && x.alive);
      if (t) return [t];
    }
    return es;
  }

  private selectTargets(u: Unit, s: SkillRow, enemyPool: Unit[]): Unit[] {
    const allies = this.alliesOf(u);
    switch (s.selector) {
      case 'self': return [u];
      case 'ally_all': return allies;
      case 'ally_lowest': return [allies.reduce((a, b) => a.hp / a.stats.hp <= b.hp / b.stats.hp ? a : b)];
      case 'enemy_all': return enemyPool;
      case 'enemy_lowest': return [enemyPool.reduce((a, b) => a.hp / a.stats.hp <= b.hp / b.stats.hp ? a : b)];
      case 'enemy_random': {
        if (!enemyPool.length) return [];
        return [enemyPool[Math.floor(this.rng() * enemyPool.length)] ?? enemyPool[0]];
      }
      default: return enemyPool.length ? [enemyPool[0]] : [];
    }
  }

  private applyEffect(u: Unit, skill: SkillRow, e: EffectDef, targets: Unit[]) {
    const ue = this.eff(u);
    let selfApplied = false; // onSelf 效果整场合一次（防 enemy_all 时重复给自身）
    for (const t0 of targets) {
      if (!t0) continue; // 空目标防御（同回合敌全灭后的残留行动）
      if (e.onSelf) { if (selfApplied) continue; selfApplied = true; }
      const t = e.onSelf ? u : t0; // onSelf 效果（如雷驰自加速）作用于施法者
      switch (e.type) {
        case 'PhysDamage':
        case 'MagDamage': {
          let hitTarget = t;
          for (let h = 0; h < e.hitCount; h++) {
            if (!hitTarget.alive) {
              const remaining = this.enemiesOf(u);
              if (!remaining.length) break;
              hitTarget = remaining.reduce((a, b) => a.hp / a.stats.hp <= b.hp / b.stats.hp ? a : b);
            }
            const roll = { hit: this.rng() < this.g.HIT_BASE, crit: this.rng() < this.g.CRIT_BASE, float: this.g.FLOAT_MIN + this.rng() * (this.g.FLOAT_MAX - this.g.FLOAT_MIN) };
            const te = this.eff(hitTarget);
            const mark = hitTarget.buffs.find(b => b.def.kind === 4 && b.def.markElement === skill.element);
            const dmg = calcDamage({
              atkStat: e.type === 'PhysDamage' ? ue.atk : ue.mag, power: e.power, isPhys: e.type === 'PhysDamage',
              attackerElement: u.element, defenderElement: hitTarget.element, skillElement: skill.element,
              defStat: e.type === 'PhysDamage' ? te.def : te.res, defenderLevel: hitTarget.level,
              dmgMod: ue.dmg, markPct: mark ? mark.def.markPct * mark.stacks : 0,
            }, roll, this.g);
            if (!roll.hit) { this.log.push(`  → ${this.n(hitTarget)} 闪避`); this.ev({ t: 'dodge', u: hitTarget.uid }); continue; }
            this.dealDamage(u, hitTarget, dmg, skill.element, roll.crit);
          }
          // 蓄势消耗
          const mo = u.buffs.find(b => b.def.modStat === 'dmg');
          if (mo) { u.buffs.splice(u.buffs.indexOf(mo), 1); }
          break;
        }
        case 'Heal': {
          const amount = Math.round(ue.mag * e.power);
          t.hp = Math.min(t.stats.hp, t.hp + amount);
          this.log.push(`  → ${this.n(t)} 回复 ${amount} 点气血`);
          this.ev({ t: 'heal', u: t.uid, a: amount, hp: t.hp });
          break;
        }
        case 'Shield': {
          const base = Math.max(ue.mag, ue.def);
          t.shield += Math.round(base * e.power);
          this.log.push(`  → ${this.n(t)} 获得护盾 ${Math.round(base * e.power)}`);
          this.ev({ t: 'shield', u: t.uid, a: Math.round(base * e.power) });
          break;
        }
        case 'ApplyBuff': {
          const def = this.cfg.buffs.get(e.buffId);
          if (!def) break;
          // 控制递减 + 控制抗性（03§5 通用规则）
          let chance = e.chance;
          if (def.kind === 2) {
            const n = u === t ? 0 : t.ctrlHistory.filter(r => this.round - r <= this.g.CTRL_DIM_WINDOW).length;
            chance *= Math.pow(this.g.CTRL_DIM, Math.min(n, 3));
            chance *= 1 - (t.buffs.reduce((a, b) => a + b.def.ctrlRes, 0));
          }
          if (this.rng() >= chance) { this.log.push(`  → ${this.n(t)} 抵抗了【${def.name}】`); break; }
          const ex = t.buffs.find(b => b.def.buffId === def.buffId);
          if (ex) { ex.stacks = Math.min(def.stacks, ex.stacks + 1); ex.remain = def.duration; }
          else t.buffs.push({ def, stacks: 1, remain: def.duration });
          if (def.kind === 2) t.ctrlHistory.push(this.round);
          this.log.push(`  → ${this.n(t)} 获得【${def.name}】`);
          this.ev({ t: 'buff', u: t.uid, b: def.name, st: ex ? ex.stacks : 1 });
          break;
        }
        case 'Taunt': {
          const duration = Math.max(1, e.duration || e.power);
          const affected = e.onSelf ? this.enemiesOf(u) : [t];
          for (const enemy of affected) {
            enemy.tauntTarget = u.uid;
            enemy.tauntRemain = Math.max(enemy.tauntRemain, duration);
          }
          this.log.push(`  → ${this.n(u)} 发起嘲讽`);
          break;
        }
        case 'RageModify': {
          t.rage = Math.max(0, Math.min(this.g.RAGE_MAX, t.rage + e.power));
          this.log.push(`  → ${this.n(t)} 怒气 ${e.power > 0 ? '+' : ''}${e.power}`);
          break;
        }
        case 'CaptureBonus': {
          t.capBonus += e.power;
          this.log.push(`  → ${this.n(t)} 捕捉准备就绪`);
          break;
        }
        case 'Detonate': {
          const burn = t.buffs.find(b => b.def.buffId === 2);
          if (burn) {
            const dmg = Math.round(this.eff(u).mag * e.power * burn.stacks);
            this.dealDamage(u, t, dmg, 4);
            t.buffs.splice(t.buffs.indexOf(burn), 1);
            this.log.push(`  → 引爆 ${t.name} 的灼烧`);
          }
          break;
        }
        default:
          break;
      }
    }
  }

  private dealDamage(attacker: Unit, t: Unit, dmg: number, skillElement: number, crit = false) {
    if (t.shield > 0) {
      const abs = Math.min(t.shield, dmg);
      t.shield -= abs; dmg -= abs;
    }
    if (dmg > 0) {
      t.hp -= dmg;
      t.rage = Math.min(this.g.RAGE_MAX, t.rage + this.g.RAGE_HIT);
      // 催眠受击解除（03§12）
      const sleep = t.buffs.find(b => b.def.control === 3);
      if (sleep) t.buffs.splice(t.buffs.indexOf(sleep), 1);
      // 冰冻受火伤解除→转为灼烧（03§5）
      if (skillElement === 4) {
        const frz = t.buffs.find(b => b.def.control === 1);
        if (frz) {
          t.buffs.splice(t.buffs.indexOf(frz), 1);
          const burn = this.cfg.buffs.get(2)!;
          t.buffs.push({ def: burn, stacks: 1, remain: burn.duration });
        }
      }
      this.log.push(`  → ${this.n(t)} 受到 ${dmg} 点伤害（剩 ${Math.max(0, t.hp)}）`);
      this.ev({ t: 'hit', u: t.uid, d: dmg, hp: Math.max(0, t.hp), c: crit ? 1 : 0 });
      if (t.hp <= 0) this.kill(t);
    } else {
      this.log.push(`  → ${this.n(t)} 的护盾吸收了全部伤害`);
      this.ev({ t: 'hit', u: t.uid, d: 0, hp: Math.max(0, t.hp), c: 0 });
    }
  }

  private kill(t: Unit) {
    t.alive = false; t.hp = 0;
    this.log.push(`  ✕ ${this.n(t)} 倒下`);
    this.ev({ t: 'death', u: t.uid });
    const sub = this.bench[t.side].shift();
    if (sub) {
      sub.rage = 50; this.units.push(sub); this.log.push(`  ▲ 替补 ${sub.name} 入场（怒气50）`);
      this.ev({ t: 'sub', u: sub.uid, n: sub.name, s: sub.side });
    } else this.units = this.units.filter(x => x !== t);
  }

  private roundEnd() {
    for (const u of this.units.filter(x => x.alive)) {
      // DOT 结算与再生
      for (const b of [...u.buffs]) {
        if (b.def.kind === 1) {
          const dmg = Math.round(u.stats.hp * b.def.dotPct * b.stacks);
          u.hp -= dmg;
          this.log.push(`R${this.round} ${this.n(u)} 因【${b.def.name}】损失 ${dmg} 点气血`);
          if (u.hp <= 0) this.kill(u);
        } else if (b.def.kind === 5 && b.def.dotPct > 0) {
          const heal = Math.round(u.stats.hp * b.def.dotPct * b.stacks);
          u.hp = Math.min(u.stats.hp, u.hp + heal);
        }
        b.remain--;
      }
      u.buffs = u.buffs.filter(b => b.remain > 0);
      u.cds = u.cds.map(c => Math.max(0, c - 1));
      u.capBonus = 0;
      if (u.tauntRemain > 0) u.tauntRemain--;
      if (u.tauntRemain <= 0) u.tauntTarget = -1;
    }
  }

  /** 玩家捕捉指令（03§10）：消耗行动回合，在敌方行动后结算 */
  tryCapture(actorUid: number, gourdBase: number, qualityCoef: number): boolean {
    const actor = this.units.find(u => u.uid === actorUid && u.alive);
    const t = this.units.find(u => u.uid === this.captureTargetUid && u.alive);
    if (!actor || !t || !t.captureable) return false;
    const rate = computeCaptureRate({
      gourdBase, qualityCoef, hpPct: t.hp / t.stats.hp,
      hasControl: this.hasControl(t),
      hasCaptureDebuff: t.buffs.some(b => b.def.captureLinked && b.def.kind !== 2),
      lvlDiff: t.level - actor.level, capBonus: actor.capBonus,
    }, this.g);
    const ok = this.rng() < rate;
    this.log.push(`R${this.round} ${this.n(actor)} 祭出祖灵葫芦（成功率 ${(rate * 100).toFixed(0)}%）→ ${ok ? '收服！' : '挣脱了'}`);
    this.ev({ t: 'cap', u: actor.uid, tu: t.uid, rt: Math.round(rate * 100), ok: ok ? 1 : 0 });
    if (ok) { this.capturedPetId = t.petId; this.outcome = 'captured'; }
    return ok;
  }
}
