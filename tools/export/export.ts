#!/usr/bin/env node
/**
 * 导表工具：严格校验 CSV，生成客户端 JSON、TS/GDScript 类型和字段字典。
 * docs/12 §1-§7
 */
import { readdirSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeStats, powerOf, type G, type Aptitudes } from '../../src/battle/stats.ts';
import { parseCsv } from './parseCsv.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const TABLES_DIR = join(ROOT, 'tables');
const OUT_DIR = join(ROOT, 'out');
const GODOT_TYPES_FILE = join(ROOT, 'scripts', 'config', 'config_types.gd');
const FIELDS_FILE = join(ROOT, 'docs', 'fields.md');

const PRIMARY_KEYS: Record<string, string[]> = {
  Enums: ['enumName', 'value'], GlobalConst: ['key'], PetBase: ['petId'],
  SkillConfig: ['skillId'], PetSkillPool: ['petId', 'slot'], BuffConfig: ['buffId'],
  EnemyGroup: ['groupId', 'slot'], StageConfig: ['stageId'], DropRule: ['dropId'],
  Crop: ['cropId'], MainQuest: ['questId'],
  EquipBase: ['equipId'], AffixPool: ['affixId'], EquipQuality: ['qualityId'],
  ItemBase: ['itemId'], StorageRule: ['categoryId'], SeasonWeather: ['seasonId'],
  Mine: ['mineId'], Building: ['buildingId'], Recipe: ['recipeId'],
  EquipSet: ['equipSetId'],
};
const CLIENT_VIS = new Set(['c', 'cs']);
const VALID_VIS = new Set(['c', 's', 'cs']);
const FIELD_NAME = /^[a-z][A-Za-z0-9]*$/;
const TYPE_NAME = /^[A-Z][A-Za-z0-9]*$/;
const INT_VALUE = /^-?(?:0|[1-9]\d*)$/;
const FLOAT_VALUE = /^-?(?:(?:0|[1-9]\d*)(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?$/;

interface RawTable {
  name: string;
  fields: string[];
  types: TypeDef[];
  typeTexts: string[];
  vis: string[];
  comments: string[];
  rows: string[][];
}

interface EffectDef {
  type: string;
  power: number;
  buffId: number;
  duration: number;
  chance: number;
  hitCount: number;
  onSelf: boolean;
}

type TypeDef =
  | { kind: 'int' | 'float' | 'bool' | 'string' | 'effect_array' }
  | { kind: 'enum' | 'ref' | 'refs'; target: string }
  | { kind: 'array'; element: 'int' | 'string'; length: number };

type Row = Record<string, unknown>;

const errors: string[] = [];
const notices: string[] = [];
const err = (rule: string, message: string): void => { errors.push(`[${rule}] ${message}`); };

function parseType(text: string): TypeDef | null {
  if (text === 'int' || text === 'float' || text === 'bool' || text === 'string') return { kind: text };
  if (text === 'array<effect>') return { kind: 'effect_array' };
  let match = /^(enum|ref|refs)<([A-Z][A-Za-z0-9]*)>$/.exec(text);
  if (!match) match = /^(enum)\(([A-Z][A-Za-z0-9]*)\)$/.exec(text);
  if (match) return { kind: match[1] as 'enum' | 'ref' | 'refs', target: match[2] };
  const arrayMatch = /^array<(int|string)>\(([1-9]\d*)\)$/.exec(text);
  if (arrayMatch) return { kind: 'array', element: arrayMatch[1] as 'int' | 'string', length: Number(arrayMatch[2]) };
  return null;
}

function strictInt(raw: string): number {
  if (!INT_VALUE.test(raw)) throw new Error('不是严格整数');
  const value = Number(raw);
  if (!Number.isSafeInteger(value)) throw new Error('超出安全整数范围');
  return value;
}

function strictFloat(raw: string): number {
  if (!FLOAT_VALUE.test(raw)) throw new Error('不是严格数字');
  const value = Number(raw);
  if (!Number.isFinite(value)) throw new Error('不是有限数字');
  return value;
}

function strictBool(raw: string): boolean {
  if (raw === 'true' || raw === '1') return true;
  if (raw === 'false' || raw === '0') return false;
  throw new Error('布尔值只允许 true/false/1/0');
}

function fixedParts(raw: string, length: number): string[] {
  const parts = raw.split(';');
  if (parts.length !== length) throw new Error(`数组长度 ${parts.length} != ${length}`);
  return parts;
}

function probability(value: number): number {
  if (!(value >= 0 && value <= 1)) throw new Error(`概率 ${value} 不在 [0,1]`);
  return value;
}

function selfCheck(): void {
  if (strictInt('-12') !== -12 || strictFloat('1.25e2') !== 125 || strictBool('0') !== false) {
    throw new Error('严格解析自检失败');
  }
  for (const invalid of ['12x', '01', '1.2']) {
    let rejected = false;
    try { strictInt(invalid); } catch { rejected = true; }
    if (!rejected) throw new Error(`严格整数自检未拒绝 ${invalid}`);
  }
  for (const invalid of ['NaN', 'Infinity', '1.2x']) {
    let rejected = false;
    try { strictFloat(invalid); } catch { rejected = true; }
    if (!rejected) throw new Error(`严格浮点自检未拒绝 ${invalid}`);
  }
  let boolRejected = false;
  let arrayRejected = false;
  let probabilityRejected = false;
  try { strictBool('yes'); } catch { boolRejected = true; }
  try { fixedParts('1;2;3', 2); } catch { arrayRejected = true; }
  try { probability(1.01); } catch { probabilityRejected = true; }
  if (!boolRejected || !arrayRejected || !probabilityRejected || parseType('array<int>') !== null || parseType('ref<petBase>') !== null) {
    throw new Error('类型与规则语法自检失败');
  }
}

function loadRaw(name: string, file: string): RawTable {
  let rows: string[][] = [];
  try {
    rows = parseCsv(readFileSync(file, 'utf8'));
  } catch (cause) {
    err('V-101', `${name}: ${(cause as Error).message}`);
  }
  if (rows.length < 4) {
    err('V-101', `${name}: 表头不足 4 行（字段/类型/可见性/注释）`);
    return { name, fields: [], types: [], typeTexts: [], vis: [], comments: [], rows: [] };
  }

  const [fields, typeTexts, vis, comments] = rows.slice(0, 4);
  const width = fields.length;
  for (const [label, header] of [['类型', typeTexts], ['可见性', vis], ['注释', comments]] as const) {
    if (header.length !== width) err('V-101', `${name}: ${label}表头列数 ${header.length} != 字段列数 ${width}`);
  }
  const seen = new Set<string>();
  fields.forEach((field, index) => {
    if (!FIELD_NAME.test(field)) err('V-101', `${name}: 字段 ${field || `#${index + 1}`} 不是 camelCase 英文名`);
    if (seen.has(field)) err('V-101', `${name}: 字段名重复 ${field}`);
    seen.add(field);
    if (!VALID_VIS.has(vis[index] ?? '')) err('V-101', `${name}.${field}: 可见性只允许 c/s/cs，实际为 ${vis[index] ?? ''}`);
    if (!(comments[index] ?? '').trim()) err('V-101', `${name}.${field}: 中文注释为空`);
  });
  const types = typeTexts.map((text, index) => {
    const parsed = parseType(text);
    if (!parsed) err('V-101', `${name}.${fields[index] ?? `#${index + 1}`}: 未知类型 ${text}`);
    return parsed ?? { kind: 'string' as const };
  });
  const dataRows = rows.slice(4).filter(row => row.some(cell => cell.trim() !== ''));
  dataRows.forEach((row, index) => {
    if (row.length !== width) err('V-101', `${name}: 数据第 ${index + 5} 行列数 ${row.length} != 表头 ${width}`);
  });
  return { name, fields, types, typeTexts, vis, comments, rows: dataRows };
}

function convertCell(
  table: string,
  field: string,
  type: TypeDef,
  raw: string,
  enums: Map<string, Set<number>>,
  pkSets: Map<string, Set<string>>,
): unknown {
  try {
    if (raw === '' && type.kind === 'string') return '';
    if (raw === '') throw new Error('非 string 字段不可为空');
    if (type.kind === 'int') return strictInt(raw);
    if (type.kind === 'float') {
      const value = strictFloat(raw);
      if (/(?:chance|probability|rate)$/i.test(field)) {
        try { probability(value); } catch { err('V-301', `${table}.${field}: 概率 ${value} 不在 [0,1]`); }
      }
      return value;
    }
    if (type.kind === 'bool') return strictBool(raw);
    if (type.kind === 'string') return raw;
    if (type.kind === 'enum') {
      const value = strictInt(raw);
      if (!enums.get(type.target)?.has(value)) err('V-201', `${table}.${field}: 枚举 ${type.target}=${value} 不存在`);
      return value;
    }
    if (type.kind === 'ref') {
      const value = strictInt(raw);
      if (!pkSets.get(type.target)?.has(String(value))) err('V-201', `${table}.${field}: 外键 ${type.target}=${value} 不存在`);
      return value;
    }
    if (type.kind === 'refs') {
      const values = raw.split(';').map(strictInt);
      for (const value of values) {
        if (!pkSets.get(type.target)?.has(String(value))) err('V-201', `${table}.${field}: 外键 ${type.target}=${value} 不存在`);
      }
      return values;
    }
    if (type.kind === 'array') {
      const parts = fixedParts(raw, type.length);
      // 区间语义（min<max）不按“偶数长度”猜测——aptitudes/requiredGroups 等并非区间对，
      // 区间约束由下方各表业务校验按字段显式执行。
      return type.element === 'int' ? parts.map(strictInt) : parts;
    }

    const effects: EffectDef[] = raw.split(';').map((segment): EffectDef => {
      const parts = segment.split('|');
      if (parts.length !== 7) throw new Error(`效果 ${segment} 字段数 ${parts.length} != 7`);
      const effect: EffectDef = {
        type: parts[0], power: strictFloat(parts[1]), buffId: strictInt(parts[2]),
        duration: strictInt(parts[3]), chance: strictFloat(parts[4]),
        hitCount: strictInt(parts[5]), onSelf: strictBool(parts[6]),
      };
      if (!effect.type) throw new Error(`效果 ${segment} 的 type 为空`);
      if (!(effect.chance >= 0 && effect.chance <= 1)) err('V-301', `${table}.${field}: 效果概率 ${effect.chance} 不在 [0,1]`);
      if (effect.type === 'ApplyBuff' && !pkSets.get('BuffConfig')?.has(String(effect.buffId))) {
        err('V-202', `${table}.${field}: BuffConfig=${effect.buffId} 不存在`);
      }
      return effect;
    });
    return effects;
  } catch (cause) {
    err('V-101', `${table}.${field}: 值「${raw}」无法按 ${typeText(type)} 解析（${(cause as Error).message}）`);
    return raw;
  }
}

function typeText(type: TypeDef): string {
  if (type.kind === 'enum' || type.kind === 'ref' || type.kind === 'refs') return `${type.kind}<${type.target}>`;
  if (type.kind === 'array') return `array<${type.element}>(${type.length})`;
  if (type.kind === 'effect_array') return 'array<effect>';
  return type.kind;
}

function validateAvailableV501(tables: Map<string, Row[]>): void {
  const initialErrorCount = errors.length;
  const required = ['MainQuest', 'StageConfig', 'EnemyGroup', 'DropRule', 'PetBase', 'PetSkillPool', 'SkillConfig'];
  for (const name of required) {
    if ((tables.get(name) ?? []).length === 0) err('V-501', `${name}: 主线冒烟所需表为空`);
  }
  const ids = (name: string, field: string): Set<number> => new Set((tables.get(name) ?? []).map(row => Number(row[field])));
  const stageIds = ids('StageConfig', 'stageId');
  const groupIds = ids('EnemyGroup', 'groupId');
  const dropIds = ids('DropRule', 'dropId');
  const petIds = ids('PetBase', 'petId');
  const skillIds = ids('SkillConfig', 'skillId');

  const questsByChapter = new Map<number, Row[]>();
  for (const quest of tables.get('MainQuest') ?? []) {
    const chapter = Number(quest.chapterId);
    const rows = questsByChapter.get(chapter) ?? [];
    rows.push(quest);
    questsByChapter.set(chapter, rows);
    if (Number(quest.goalType) === 1 && !stageIds.has(Number(quest.targetId))) {
      err('V-501', `MainQuest=${quest.questId}: 通关目标 StageConfig=${quest.targetId} 不存在`);
    }
  }
  for (const [chapter, quests] of questsByChapter) {
    const orders = quests.map(row => Number(row.order)).sort((a, b) => a - b);
    orders.forEach((order, index) => {
      if (order !== index + 1) err('V-501', `MainQuest: 章节 ${chapter} 顺序不可达，期望 ${index + 1} 实际 ${order}`);
    });
  }
  const usedGroups = new Set<number>();
  for (const stage of tables.get('StageConfig') ?? []) {
    for (const groupId of stage.waves as number[]) {
      usedGroups.add(groupId);
      if (!groupIds.has(groupId)) err('V-501', `StageConfig=${stage.stageId}: EnemyGroup=${groupId} 不存在`);
    }
    if (!dropIds.has(Number(stage.dropId))) err('V-501', `StageConfig=${stage.stageId}: DropRule=${stage.dropId} 不存在`);
  }
  for (const groupId of usedGroups) {
    if (!(tables.get('EnemyGroup') ?? []).some(row => Number(row.groupId) === groupId)) {
      err('V-501', `StageConfig 引用的 EnemyGroup=${groupId} 没有敌人`);
    }
  }
  for (const enemy of tables.get('EnemyGroup') ?? []) {
    if (!petIds.has(Number(enemy.petId))) err('V-501', `EnemyGroup=${enemy.groupId}: PetBase=${enemy.petId} 不存在`);
  }
  const slotsByPet = new Map<number, Set<number>>();
  for (const pool of tables.get('PetSkillPool') ?? []) {
    const petId = Number(pool.petId);
    if (!petIds.has(petId)) err('V-501', `PetSkillPool: PetBase=${petId} 不存在`);
    if (!skillIds.has(Number(pool.skillId))) err('V-501', `PetSkillPool: SkillConfig=${pool.skillId} 不存在`);
    const slots = slotsByPet.get(petId) ?? new Set<number>();
    slots.add(Number(pool.slot));
    slotsByPet.set(petId, slots);
  }
  for (const petId of petIds) {
    const slots = slotsByPet.get(petId) ?? new Set<number>();
    if (![0, 1, 2, 3].every(slot => slots.has(slot))) err('V-501', `PetBase=${petId}: 技能槽 0..3 不完整`);
  }
  if (errors.length === initialErrorCount) {
    notices.push('[V-501] AVAILABLE_CHECKS_PASS: 主线顺序及 Stage/Enemy/Drop/Skill/Pet 引用通过');
  }
  notices.push('[V-501] NOT_IMPLEMENTED (non-blocking Phase 0): 当前表集无商店表，无法检查“商店有货”');
}

function tsType(type: TypeDef): string {
  if (type.kind === 'int' || type.kind === 'float' || type.kind === 'enum' || type.kind === 'ref') return 'number';
  if (type.kind === 'bool') return 'boolean';
  if (type.kind === 'refs') return 'number[]';
  if (type.kind === 'array') return type.length === 2 ? `[${type.element === 'int' ? 'number' : 'string'}, ${type.element === 'int' ? 'number' : 'string'}]` : `${type.element === 'int' ? 'number' : 'string'}[]`;
  if (type.kind === 'effect_array') return 'EffectDef[]';
  return 'string';
}

function generateTypes(raws: Map<string, RawTable>): void {
  let dts = '// 自动生成：导表产物，勿手改（docs/12 §7）\nexport interface EffectDef {\n  type: string; power: number; buffId: number; duration: number; chance: number; hitCount: number; onSelf: boolean;\n}\n';
  for (const [name, table] of raws) {
    if (name === 'Enums' || name === 'GlobalConst') continue;
    dts += `\nexport interface ${name}Row {\n`;
    table.fields.forEach((field, index) => {
      if (CLIENT_VIS.has(table.vis[index])) dts += `  ${field}: ${tsType(table.types[index])};\n`;
    });
    dts += '}\n';
  }
  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(join(OUT_DIR, 'types.d.ts'), dts);

  const fieldTypes: Record<string, Record<string, string>> = {};
  const arrayLengths: Record<string, Record<string, number>> = {};
  for (const [name, table] of raws) {
    fieldTypes[name] = {};
    arrayLengths[name] = {};
    table.fields.forEach((field, index) => {
      if (!CLIENT_VIS.has(table.vis[index])) return;
      fieldTypes[name][field] = typeText(table.types[index]);
      if (table.types[index].kind === 'array') arrayLengths[name][field] = table.types[index].length;
    });
  }
  const gd = [
    '## 自动生成：配置表字段元数据，勿手改。',
    '## doc: 12-导表与数据管线 §1-§2/§7',
    '# gdformat: disable',
    'class_name ConfigTypes',
    'extends RefCounted',
    '',
    `const PRIMARY_KEYS: Dictionary = ${toGdLiteral(PRIMARY_KEYS)}`,
    `const FIELD_TYPES: Dictionary = ${toGdLiteral(fieldTypes)}`,
    `const ARRAY_LENGTHS: Dictionary = ${toGdLiteral(arrayLengths)}`,
    '',
  ].join('\n');
  writeFileSync(GODOT_TYPES_FILE, gd);
}

function toGdLiteral(value: unknown, indent = 0): string {
  if (Array.isArray(value)) return `[${value.map(item => toGdLiteral(item, indent)).join(', ')}]`;
  if (value !== null && typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length === 0) return '{}';
    const pad = '\t'.repeat(indent + 1);
    const closePad = '\t'.repeat(indent);
    const lines = entries.map(([key, item]) => {
      return `${pad}${JSON.stringify(key)}: ${toGdLiteral(item, indent + 1)}`;
    });
    return `{\n${lines.join(',\n')}\n${closePad}}`;
  }
  return JSON.stringify(value);
}

function generateFields(raws: Map<string, RawTable>): void {
  const lines = ['# 配置字段字典', '', '> 自动生成自 `tables/*.csv` 四行表头，勿手改。来源：docs/12 §1-§4。', ''];
  for (const [name, table] of raws) {
    lines.push(`## ${name}`, '', '| 字段 | 类型 | 可见性 | 说明 |', '|---|---|---|---|');
    table.fields.forEach((field, index) => {
      const comment = table.comments[index].replaceAll('|', '\\|').replaceAll('\n', '<br>');
      lines.push(`| ${field} | \`${table.typeTexts[index]}\` | \`${table.vis[index]}\` | ${comment} |`);
    });
    lines.push('');
  }
  writeFileSync(FIELDS_FILE, lines.join('\n'));
}

function main(): void {
  selfCheck();
  const files = readdirSync(TABLES_DIR).filter(file => file.endsWith('.csv')).sort();
  const raws = new Map<string, RawTable>();
  for (const file of files) {
    const name = file.slice(0, -4);
    if (!TYPE_NAME.test(name)) err('V-101', `${file}: 表名必须为 PascalCase 英文名`);
    raws.set(name, loadRaw(name, join(TABLES_DIR, file)));
  }

  for (const name of Object.keys(PRIMARY_KEYS)) {
    if (!raws.has(name)) err('V-101', `缺少核心表 ${name}.csv`);
  }
  const enumRaw = raws.get('Enums');
  const enums = new Map<string, Set<number>>();
  if (enumRaw) {
    const nameIndex = enumRaw.fields.indexOf('enumName');
    const valueIndex = enumRaw.fields.indexOf('value');
    for (const row of enumRaw.rows) {
      const enumName = row[nameIndex] ?? '';
      let value = 0;
      try { value = strictInt(row[valueIndex] ?? ''); } catch { err('V-101', `Enums.value: 非法整数 ${row[valueIndex] ?? ''}`); }
      const values = enums.get(enumName) ?? new Set<number>();
      values.add(value);
      enums.set(enumName, values);
    }
  }

  const pkSets = new Map<string, Set<string>>();
  for (const [name, table] of raws) {
    const keys = PRIMARY_KEYS[name] ?? [];
    if (keys.length === 0) continue;
    const indexes = keys.map(key => table.fields.indexOf(key));
    if (indexes.some(index => index < 0)) {
      err('V-101', `${name}: 缺少主键字段 ${keys.join(',')}`);
      continue;
    }
    const unique = new Set<string>();
    const firstKeys = new Set<string>();
    for (const row of table.rows) {
      const values = indexes.map(index => row[index] ?? '');
      if (values.some(value => value.trim() === '')) err('V-102', `${name}: 主键为空`);
      const key = values.join('|');
      if (unique.has(key)) err('V-102', `${name}: 主键重复 ${key}`);
      unique.add(key);
      firstKeys.add(values[0]);
    }
    pkSets.set(name, firstKeys);
  }

  const converted = new Map<string, Row[]>();
  for (const [name, table] of raws) {
    const rows: Row[] = [];
    for (const rawRow of table.rows) {
      const row: Row = {};
      table.fields.forEach((field, index) => {
        const value = convertCell(name, field, table.types[index], rawRow[index] ?? '', enums, pkSets);
        if (CLIENT_VIS.has(table.vis[index])) row[field] = value;
      });
      rows.push(row);
    }
    converted.set(name, rows);
  }

  for (const drop of converted.get('DropRule') ?? []) {
    const weights = ['wWhite', 'wGreen', 'wBlue', 'wPurple', 'wOrange', 'wRed'].map(field => Number(drop[field]));
    if (weights.some(weight => weight < 0 || weight > 100)) err('V-301', `DropRule=${drop.dropId}: 权重必须在 [0,100]`);
    if (weights.reduce((sum, weight) => sum + weight, 0) <= 0) err('V-301', `DropRule=${drop.dropId}: 权重和必须 > 0`);
  }
  for (const buff of converted.get('BuffConfig') ?? []) {
    for (const field of ['modPct', 'modPct2', 'dotPct', 'markPct', 'ctrlRes']) {
      const value = Number(buff[field]);
      if (!(value >= -1 && value <= 1)) err('V-301', `BuffConfig=${buff.buffId}: ${field}=${value} 不在 [-1,1]`);
    }
  }
  for (const drop of converted.get('DropRule') ?? []) {
    if (!['settlement', 'item'].includes(String(drop.pityUnit))) err('V-301', `DropRule=${drop.dropId}: pityUnit 只允许 settlement/item`);
    if (!['monster_level', 'nightmare_layer'].includes(String(drop.equipLvMode))) err('V-301', `DropRule=${drop.dropId}: equipLvMode 只允许 monster_level/nightmare_layer`);
    if (Number(drop.equipLvOffsetMin) > Number(drop.equipLvOffsetMax)) err('V-301', `DropRule=${drop.dropId}: 等级偏移区间倒置`);
    if (Number(drop.pityQuality) !== 0 && Number(drop.pityCount) <= 0) err('V-301', `DropRule=${drop.dropId}: 配置保底品质但保底次数 <= 0`);
  }
  for (const equip of converted.get('EquipBase') ?? []) {
    if (!(Number(equip.baseValue) > 0)) err('V-301', `EquipBase=${equip.equipId}: baseValue 必须 > 0`);
    if (!(Number(equip.weight) > 0)) err('V-301', `EquipBase=${equip.equipId}: weight 必须 > 0`);
    if (![1, 2, 3].includes(Number(equip.slot))) err('V-301', `EquipBase=${equip.equipId}: slot 只允许 1武器/2防具/3饰品`);
  }
  const equipStats = new Set<string>();
  for (const affix of converted.get('AffixPool') ?? []) {
    if (!(Number(affix.min) < Number(affix.max))) err('V-301', `AffixPool=${affix.affixId}: 区间必须 min < max`);
    if (!(Number(affix.weight) > 0)) err('V-301', `AffixPool=${affix.affixId}: weight 必须 > 0`);
    if (Number(affix.qualityMin) > Number(affix.qualityMax)) err('V-301', `AffixPool=${affix.affixId}: 品质区间倒置`);
    if (![1, 2].includes(Number(affix.rollType))) err('V-301', `AffixPool=${affix.affixId}: rollType 只允许 1百分比/2平面值`);
    if (equipStats.has(String(affix.stat))) err('V-301', `AffixPool: stat=${affix.stat} 重复（同名词条不重复规则）`);
    equipStats.add(String(affix.stat));
  }
  for (const quality of converted.get('EquipQuality') ?? []) {
    if (Number(quality.affixMin) > Number(quality.affixMax)) err('V-301', `EquipQuality=${quality.qualityId}: 词条数区间倒置`);
  }
  validateAvailableV501(converted);

  mkdirSync(join(OUT_DIR, 'config'), { recursive: true });
  const jsonTables: Record<string, unknown> = {};
  for (const [name, rows] of converted) {
    if (name === 'Enums') {
      const grouped: Record<string, Record<number, string>> = {};
      for (const row of rows) (grouped[String(row.enumName)] ??= {})[Number(row.value)] = String(row.label);
      jsonTables[name] = grouped;
    } else if (name === 'GlobalConst') {
      const globals: G = {};
      for (const row of rows as Array<{ key: string; value: number }>) globals[row.key] = row.value;
      jsonTables[name] = globals;
    } else jsonTables[name] = rows;
  }

  const globals = jsonTables.GlobalConst as G;
  const aptitudes: Aptitudes = { atk: 1000, def: 1000, hp: 1000, spd: 1000, mag: 1000 };
  const offsets = { hp: 0, atk: 0, def: 0, spd: 0, mag: 0, res: 0 };
  const anchors: Array<[number, number, number]> = [
    [15, 1, globals.ANCHOR_POW_15], [40, 2, globals.ANCHOR_POW_40],
    [80, 4, globals.ANCHOR_POW_80], [120, 8, globals.ANCHOR_POW_120],
  ];
  const tolerance = globals.ANCHOR_TOL;
  const report = ['# 平衡报表（V-401）', '', '| 等级 | 境界突破数 | 实算战力 | 锚点 | 偏差 | 判定 |', '|---|---|---|---|---|---|'];
  let v401Passed = true;
  for (const [level, realmBreaks, anchor] of anchors) {
    const power = powerOf(computeStats(1, offsets, level, aptitudes, realmBreaks, globals), globals);
    const deviation = (power - anchor) / anchor;
    const passed = Math.abs(deviation) <= tolerance;
    v401Passed &&= passed;
    report.push(`| ${level} | ${realmBreaks} | ${Math.round(power)} | ${anchor} | ${(deviation * 100).toFixed(1)}% | ${passed ? 'PASS' : 'FAIL'} |`);
  }
  report.push('', `- 容差 +/-${(tolerance * 100).toFixed(0)}%：${v401Passed ? 'PASS' : 'FAIL（阻塞）'}`);
  writeFileSync(join(OUT_DIR, 'report.md'), report.join('\n'));
  if (!v401Passed) err('V-401', '等级-战力曲线超出锚点容差，详见 out/report.md');

  notices.push('[V-202] NOT_IMPLEMENTED (non-blocking Phase 0): Buff 引用已检查；当前无 Item/Text 表，奖励 itemId/文案 textId 无法检查');
  notices.push('[V-302] NOT_IMPLEMENTED (non-blocking Phase 0): 尚无 deprecated 字段与历史 ID 清单，无法检查 ID 复用');
  notices.push('[V-402] NOT_IMPLEMENTED (non-blocking Phase 0): 尚无挑战里程碑与三天成长模拟输入');
  notices.push('[V-403] NOT_IMPLEMENTED (non-blocking Phase 0): 尚无完整经济产消表，无法运行 30 天模拟');

  if (errors.length > 0) {
    console.error(`校验失败 ${errors.length} 条：`);
    errors.forEach(message => console.error(`  ${message}`));
    notices.forEach(message => console.log(message));
    process.exit(1);
  }

  for (const [name, data] of Object.entries(jsonTables)) {
    writeFileSync(join(OUT_DIR, 'config', `${name}.json`), JSON.stringify(data, null, 1));
  }
  generateTypes(raws);
  generateFields(raws);
  const rowCount = [...converted.values()].reduce((sum, rows) => sum + rows.length, 0);
  console.log(`导表完成：${converted.size} 张表 / ${rowCount} 行数据 -> out/config`);
  console.log('[V-101/102/201/301/401] PASS');
  notices.forEach(message => console.log(message));
}

main();
