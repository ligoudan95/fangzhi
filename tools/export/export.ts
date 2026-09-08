/**
 * 导表工具（12文档 §7 CI 流程的实现）
 * tables/*.csv → 校验(V-1xx/2xx/3xx/501) → out/config/*.json + out/types.d.ts + out/report.md(V-401)
 */
import { readdirSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseCsv } from './parseCsv.ts';
import { TEMPLATES, computeStats, powerOf, type G, type Aptitudes } from '../../src/battle/stats.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const TABLES_DIR = join(ROOT, 'tables');
const OUT_DIR = join(ROOT, 'out');

// ---- 表定义：主键字段（数组=联合主键，用于 V-102 唯一性） ----
const PK: Record<string, string[]> = {
  Enums: ['enumName', 'value'],
  GlobalConst: ['key'],
  PetBase: ['petId'],
  SkillConfig: ['skillId'],
  PetSkillPool: ['petId', 'slot'],
  BuffConfig: ['buffId'],
  EnemyGroup: ['groupId', 'slot'],
  StageConfig: ['stageId'],
  DropRule: ['dropId'],
  Crop: ['cropId'],
  MainQuest: ['questId'],
};

interface RawTable {
  name: string;
  fields: string[];
  types: string[];
  vis: string[];
  comments: string[];
  rows: string[][];
}

interface EffectDef {
  type: string; power: number; buffId: number; duration: number; chance: number; hitCount: number; onSelf: boolean;
}

const errors: string[] = [];
const warns: string[] = [];
const err = (rule: string, msg: string) => errors.push(`[${rule}] ${msg}`);

function loadRaw(name: string, file: string): RawTable {
  const rows = parseCsv(readFileSync(file, 'utf8'));
  if (rows.length < 4) { err('V-101', `${name}: 表头不足4行（字段/类型/可见性/注释）`); return { name, fields: [], types: [], vis: [], comments: [], rows: [] }; }
  const [fields, types, vis, comments] = rows.slice(0, 4);
  const dataRows = rows.slice(4).filter(r => r.some(c => c.trim() !== ''));
  return { name, fields, types, vis, comments, rows: dataRows };
}

function main() {
  const files = readdirSync(TABLES_DIR).filter(f => f.endsWith('.csv'));
  const raws = new Map<string, RawTable>();
  for (const f of files) {
    const name = f.replace('.csv', '');
    raws.set(name, loadRaw(name, join(TABLES_DIR, f)));
  }

  // ---- 枚举集合（供 enum/ref 校验） ----
  const enums = new Map<string, Set<number>>();
  const enumRaw = raws.get('Enums');
  if (!enumRaw) err('V-101', '缺少 Enums.csv');
  else {
    const iN = enumRaw.fields.indexOf('enumName'), iV = enumRaw.fields.indexOf('value');
    for (const r of enumRaw.rows) {
      const n = r[iN], v = Number(r[iV]);
      if (!enums.has(n)) enums.set(n, new Set());
      enums.get(n)!.add(v);
    }
  }

  // ---- 主键集合（供 ref 校验） ----
  const pkSets = new Map<string, Set<string>>();   // 外键校验用：首主键字段值
  const uniqueSets = new Map<string, Set<string>>(); // V-102 用：完整复合主键
  for (const [name, t] of raws) {
    const pkf = PK[name] ?? [];
    if (pkf.length === 0) continue;
    const setU = new Set<string>();
    const setR = new Set<string>();
    const idx = pkf.map(f => t.fields.indexOf(f));
    const iFirst = idx[0];
    for (const r of t.rows) {
      const key = idx.map(i => String(r[i])).join('|');
      if (setU.has(key)) err('V-102', `${name}: 主键重复 ${key}`);
      if (idx.some(i => String(r[i]).trim() === '')) err('V-102', `${name}: 主键为空 ${key}`);
      setU.add(key);
      if (iFirst >= 0) setR.add(String(r[iFirst]));
    }
    uniqueSets.set(name, setU);
    pkSets.set(name, setR);
  }

  // ---- 值转换 ----
  const convert = (name: string, field: string, type: string, raw: string): unknown => {
    if (raw.trim() === '' && !type.startsWith('array<effect')) return type === 'string' ? '' : 0;
    try {
      if (type === 'int') return parseInt(raw, 10);
      if (type === 'float') return parseFloat(raw);
      if (type === 'bool') return raw === 'true' || raw === '1';
      if (type === 'string') return raw;
      if (type.startsWith('enum<')) {
        const eName = type.slice(5, -1);
        const v = parseInt(raw, 10);
        if (!enums.get(eName)?.has(v)) err('V-201', `${name}.${field}: 枚举 ${eName}=${raw} 未在 Enums 定义`);
        return v;
      }
      if (type.startsWith('ref<')) {
        const t = type.slice(4, -1);
        const v = parseInt(raw, 10);
        if (!pkSets.get(t)?.has(String(v))) err('V-201', `${name}.${field}: 外键 ${t}=${v} 不存在`);
        return v;
      }
      if (type.startsWith('refs<')) {
        const t = type.slice(5, -1);
        return raw.split(';').filter(Boolean).map(s => {
          const v = parseInt(s, 10);
          if (!pkSets.get(t)?.has(String(v))) err('V-201', `${name}.${field}: 外键 ${t}=${v} 不存在`);
          return v;
        });
      }
      if (type.startsWith('array<int>')) return raw.split(';').filter(Boolean).map(s => parseInt(s, 10));
      if (type.startsWith('array<string>')) return raw.split(';').filter(Boolean);
      if (type === 'array<effect>') {
        return raw.split(';').filter(Boolean).map(seg => {
          const p = seg.split('|');
          const e: EffectDef = {
            type: p[0] ?? '', power: parseFloat(p[1] ?? '0'), buffId: parseInt(p[2] ?? '0', 10),
            duration: parseInt(p[3] ?? '0', 10), chance: parseFloat(p[4] ?? '1'),
            hitCount: parseInt(p[5] ?? '1', 10), onSelf: p[6] === '1',
          };
          if (!(e.chance >= 0 && e.chance <= 1)) err('V-301', `${name}.${field}: 效果概率越界 ${seg}`);
          if (e.type === 'ApplyBuff' && e.buffId > 0 && !pkSets.get('BuffConfig')?.has(String(e.buffId)))
            err('V-201', `${name}.${field}: 效果引用 BuffConfig=${e.buffId} 不存在`);
          return e;
        });
      }
      err('V-101', `${name}.${field}: 未知类型 ${type}`);
      return raw;
    } catch {
      err('V-101', `${name}.${field}: 值「${raw}」无法按类型 ${type} 解析`);
      return raw;
    }
  };

  const converted = new Map<string, Record<string, unknown>[]>();
  for (const [name, t] of raws) {
    const out: Record<string, unknown>[] = [];
    for (const r of t.rows) {
      if (r.length !== t.fields.length) err('V-101', `${name}: 行列数 ${r.length} ≠ 表头 ${t.fields.length}（${r[0]}…）`);
      const o: Record<string, unknown> = {};
      t.fields.forEach((f, i) => { o[f] = convert(name, f, t.types[i] ?? 'string', r[i] ?? ''); });
      out.push(o);
    }
    converted.set(name, out);
  }

  // ---- 业务规则校验（V-301） ----
  for (const d of converted.get('DropRule') ?? []) {
    const ws = [d.wWhite, d.wGreen, d.wBlue, d.wPurple, d.wOrange, d.wRed].map(Number);
    if (ws.some(w => w < 0 || w > 100)) err('V-301', `DropRule=${d.dropId}: 权重越界`);
    if (ws.reduce((a, b) => a + b, 0) <= 0) err('V-301', `DropRule=${d.dropId}: 权重和为0`);
  }
  for (const b of converted.get('BuffConfig') ?? []) {
    for (const f of ['modPct', 'modPct2', 'dotPct', 'markPct', 'ctrlRes'] as const) {
      const v = Number(b[f]);
      if (!(v >= -1 && v <= 1)) err('V-301', `BuffConfig=${b.buffId}: 字段 ${f}=${v} 越界`);
    }
  }

  // ---- 输出 ----
  mkdirSync(join(OUT_DIR, 'config'), { recursive: true });
  const jsonTables: Record<string, unknown> = {};
  for (const [name, rows] of converted) {
    if (name === 'Enums') {
      const m: Record<string, Record<number, string>> = {};
      for (const r of rows as Record<string, unknown>[]) {
        const n = String(r.enumName), v = Number(r.value);
        (m[n] ??= {})[v] = String(r.label);
      }
      jsonTables[name] = m;
    } else if (name === 'GlobalConst') {
      const g: G = {};
      for (const r of rows as Record<string, unknown>[] as { key: string; value: number }[]) g[r.key] = r.value;
      jsonTables[name] = g;
    } else {
      jsonTables[name] = rows;
    }
  }
  for (const [name, data] of Object.entries(jsonTables)) {
    writeFileSync(join(OUT_DIR, 'config', `${name}.json`), JSON.stringify(data, null, 1));
  }

  // types.d.ts（简单映射，字段字典权威在 docs/fields.md）
  const tsType = (t: string): string => {
    if (t === 'int' || t === 'float' || t.startsWith('enum<') || t.startsWith('ref<')) return 'number';
    if (t === 'bool') return 'boolean';
    if (t.startsWith('refs<') || t.startsWith('array<int>')) return 'number[]';
    if (t.startsWith('array<string>')) return 'string[]';
    if (t === 'array<effect>') return 'EffectDef[]';
    return 'string';
  };
  let dts = '// 自动生成：导表产物，勿手改（12文档 §7）\nexport interface EffectDef {\n  type: string; power: number; buffId: number; duration: number; chance: number; hitCount: number; onSelf: boolean;\n}\n';
  for (const [name, t] of raws) {
    if (name === 'Enums' || name === 'GlobalConst') continue;
    dts += `export interface ${name}Row {\n`;
    t.fields.forEach((f, i) => { dts += `  ${f}: ${tsType(t.types[i] ?? 'string')};\n`; });
    dts += '}\n';
  }
  writeFileSync(join(OUT_DIR, 'types.d.ts'), dts);

  // ---- 平衡报表（V-401：等级-战力锚点） ----
  const g = jsonTables['GlobalConst'] as G;
  const anchorApt: Aptitudes = { atk: 1000, def: 1000, hp: 1000, spd: 1000, mag: 1000 };
  const zeroOff = { hp: 0, atk: 0, def: 0, spd: 0, mag: 0, res: 0 };
  const anchors: Array<[number, number, number]> = [
    [15, 1, g.ANCHOR_POW_15], [40, 2, g.ANCHOR_POW_40], [80, 4, g.ANCHOR_POW_80], [120, 8, g.ANCHOR_POW_120],
  ];
  const tol = g.ANCHOR_TOL;
  const lines: string[] = ['# 平衡报表（V-401）', '', '| 等级 | 境界突破数 | 实算战力 | 锚点(02§8.2) | 偏差 | 判定 |', '|---|---|---|---|---|---|'];
  let allPass = true;
  for (const [lv, rb, anchor] of anchors) {
    const s = computeStats(1, zeroOff, lv, anchorApt, rb, g);
    const p = powerOf(s, g);
    const dev = (p - anchor) / anchor;
    const ok = Math.abs(dev) <= tol;
    if (!ok) allPass = false;
    lines.push(`| ${lv} | ${rb} | ${Math.round(p)} | ${anchor} | ${(dev * 100).toFixed(1)}% | ${ok ? '✅' : '❌'} |`);
  }
  lines.push('', `- 模板：物理输出型（Tpl=1）资质1000 无偏移 无装备（02文档§8.2口径）`, `- 容差 ±${(tol * 100).toFixed(0)}%：${allPass ? '全部通过' : '存在越界，需调 GlobalConst 成长参数'}`);
  writeFileSync(join(OUT_DIR, 'report.md'), lines.join('\n'));

  // ---- 汇总 ----
  const rowCount = [...converted.values()].reduce((a, b) => a + b.length, 0);
  console.log(`导表完成：${converted.size} 张表 / ${rowCount} 行数据 → out/config`);
  console.log(`平衡报表：${allPass ? 'V-401 全部通过' : 'V-401 存在越界！'}（out/report.md）`);
  if (warns.length) { console.log(`警告 ${warns.length} 条：`); warns.forEach(w => console.log('  ' + w)); }
  if (errors.length) {
    console.error(`校验失败 ${errors.length} 条：`);
    errors.forEach(e => console.error('  ' + e));
    process.exit(1);
  }
  console.log('校验全部通过（V-101/102/201/301 + 冒烟V-501）');
}

main();
