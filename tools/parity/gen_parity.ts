/**
 * 对拍期望日志生成（docs/13 §6）：用 TS 数值基准引擎按种子清单跑三个场景，
 * 产出 out/parity/expected/seed_<n>.log；Godot 侧 tests/parity_runner.gd
 * 用相同场景与种子逐行 diff。种子清单 tools/parity/seeds.json 入 Git，日志产物不入库。
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { Battle } from '../../src/battle/engine.ts';
import { loadConfig, makePetInput, groupInputs } from '../../src/config/load.ts';

const ROOT = join(import.meta.dirname, '..', '..');
const cfg = loadConfig();
const g = cfg.g;
const seeds: number[] = JSON.parse(readFileSync(join(ROOT, 'tools/parity/seeds.json'), 'utf8'));
const OUT_DIR = join(ROOT, 'out', 'parity', 'expected');

mkdirSync(OUT_DIR, { recursive: true });

for (const seed of seeds) {
  const lines: string[] = [`### seed=${seed}`];

  // 场景1：关卡4 黑风林·雾深处（标准 3v3）
  {
    const b = new Battle(
      cfg,
      [
        makePetInput(cfg, 1001, 12, 900, 1),
        makePetInput(cfg, 1002, 12, 900, 1),
        makePetInput(cfg, 1005, 12, 950, 1),
      ],
      groupInputs(cfg, 4),
      seed,
    );
    const r = b.run();
    lines.push(`[stage4] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
  }

  // 场景2：关卡6 Boss 域主藤皇（高压战斗，多机制覆盖）
  {
    const b = new Battle(
      cfg,
      [
        makePetInput(cfg, 1006, 20, 1000, 2),
        makePetInput(cfg, 1002, 20, 950, 2),
        makePetInput(cfg, 1011, 20, 950, 2),
      ],
      groupInputs(cfg, 6),
      seed,
    );
    const r = b.run();
    lines.push(`[stage6] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
  }

  // 场景3：捕捉战（关卡2 外围藤影，玄冰鲤控场）——覆盖 tryCapture 与捕捉率日志
  {
    const b = new Battle(
      cfg,
      [
        makePetInput(cfg, 1009, 10, 900, 1),
        makePetInput(cfg, 1001, 10, 900, 1),
        makePetInput(cfg, 1005, 10, 950, 1),
      ],
      groupInputs(cfg, 2),
      seed,
      { capture: true },
    );
    b.tryCapture(1, g.CAP_GOURD_JADE, g.CAP_Q3);
    if (!b.outcome) b.tryCapture(1, g.CAP_GOURD_WOOD, g.CAP_Q1);
    const r = b.run();
    lines.push(`[capture] outcome=${r.outcome} rounds=${r.rounds}`);
    lines.push(...r.log);
  }

  writeFileSync(join(OUT_DIR, `seed_${seed}.log`), lines.join('\n') + '\n');
}

console.log(`对拍期望日志已生成：${seeds.length} 个种子 × 3 场景 → out/parity/expected/`);
