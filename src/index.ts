/**
 * 演示入口：一场关卡战斗 + 一次捕捉战斗（Phase 0 验证用）
 * 运行：npm run demo
 */
import { Battle, computeCaptureRate } from './battle/engine.ts';
import { powerOf } from './battle/stats.ts';
import { loadConfig, makePetInput, groupInputs } from './config/load.ts';

const cfg = loadConfig();
const G = cfg.g;

// ---- 演示1：推图战斗（关卡4 黑风林·雾深处）----
console.log('====== 演示1：关卡4 黑风林·雾深处 ======');
const teamA = [
  makePetInput(cfg, 1001, 12, 900, 1),   // 灰岩獒（坦克）
  makePetInput(cfg, 1002, 12, 900, 1),   // 桃夭狐（治疗）
  makePetInput(cfg, 1005, 12, 950, 1),   // 朱羽雉（输出）
];
const b1 = new Battle(cfg, teamA, groupInputs(cfg, 4), 20260908);
const r1 = b1.run();
r1.log.forEach(l => console.log(l));
console.log(`结果：${r1.outcome} / ${r1.rounds} 回合\n`);

// ---- 演示2：捕捉战斗（关卡2 外围藤影，玄冰鲤不在场——用标准捕捉流程演示公式与收妖）----
console.log('====== 演示2：捕捉数值样例（02文档§5验收口径）======');
const cases: Array<[string, Parameters<typeof computeCaptureRate>[0]]> = [
  ['玉葫芦收玄兽（15%血+冰冻）', { gourdBase: G.CAP_GOURD_JADE, qualityCoef: G.CAP_Q3, hpPct: 0.15, hasControl: true, hasCaptureDebuff: false, lvlDiff: 0, capBonus: 0 }],
  ['木葫芦收凡兽（15%血+中毒）', { gourdBase: G.CAP_GOURD_WOOD, qualityCoef: G.CAP_Q1, hpPct: 0.15, hasControl: false, hasCaptureDebuff: true, lvlDiff: 0, capBonus: 0 }],
  ['满血强行收灵兽（反面教材）', { gourdBase: G.CAP_GOURD_WOOD, qualityCoef: G.CAP_Q2, hpPct: 1.0, hasControl: false, hasCaptureDebuff: false, lvlDiff: 5, capBonus: 0 }],
];
for (const [name, inp] of cases) {
  console.log(`${name}：成功率 ${(computeCaptureRate(inp, G) * 100).toFixed(1)}%`);
}

// ---- 演示3：队伍战力 vs 关卡推荐战力 ----
console.log('\n====== 演示3：战力对照 ======');
const stages = JSON.parse((await import('node:fs')).readFileSync('out/config/StageConfig.json', 'utf8')) as { stageId: number; name: string; power: number }[];
for (const st of stages) console.log(`关卡${st.stageId} ${st.name}：推荐战力 ${st.power}`);
