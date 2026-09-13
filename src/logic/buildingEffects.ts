/**
 * 建筑效果（TS 基准）——与 scripts/logic/building_effects.gd 逐位一致（docs/05 §2 / docs/26 §4.1）。
 * 纯函数：等级→效果值（effectBase + effectStep × 等级）；各系统按 effectKind 消费。
 * 城防（kind 5）暂只提供数值，战斗消费待 docs/05 §9 数值细则。
 */

export interface BuildingState { buildingId: number; level: number }
export interface BuildingRow {
  buildingId: number; maxLevel: number; effectKind: number;
  effectBase: number; effectStep: number;
}

/** 建筑表 ID 速记（docs/05 §2） */
export const HALL = 1;
export const BARN = 3;
export const FARM = 4;
export const MINE = 5;
export const FORGE = 7;
export const ALCHEMY = 8;
export const WAREHOUSE = 9;
export const TOTEM = 12;

export function levelOf(buildings: BuildingState[], buildingId: number): number {
  return buildings.find(b => b.buildingId === buildingId)?.level ?? 0;
}

/** 效果值 = effectBase + effectStep × 等级（CSV 为数值权威） */
export function effectValue(buildings: BuildingState[], buildingId: number, rows: BuildingRow[]): number {
  const row = rows.find(r => r.buildingId === buildingId);
  if (!row) return 0;
  return row.effectBase + row.effectStep * levelOf(buildings, buildingId);
}

/** 灵田田位数（kind 1） */
export function fieldSlots(buildings: BuildingState[], rows: BuildingRow[]): number {
  return Math.trunc(effectValue(buildings, FARM, rows));
}

/** 矿场同时开采矿层数（kind 1） */
export function mineSlots(buildings: BuildingState[], rows: BuildingRow[]): number {
  return Math.trunc(effectValue(buildings, MINE, rows));
}

/** 锻造炉/药庐生产队列容量（kind 3，向下取整至少 1） */
export function queueCap(buildings: BuildingState[], stationBuildingId: number, rows: BuildingRow[]): number {
  return Math.max(1, Math.floor(effectValue(buildings, stationBuildingId, rows)));
}

/** 仓库储量上限倍率（kind 2，至少 1.0） */
export function storageCapMult(buildings: BuildingState[], rows: BuildingRow[]): number {
  return Math.max(1.0, effectValue(buildings, WAREHOUSE, rows));
}

/** 离线收益上限秒数（图腾柱 kind 1：效果值按小时解释，钳在 [基础, 图腾上限]） */
export function offlineCapSec(
  buildings: BuildingState[], rows: BuildingRow[],
  g: { OFFLINE_CAP_BASE_SEC: number; OFFLINE_CAP_TOTEM_SEC: number },
): number {
  const base = g.OFFLINE_CAP_BASE_SEC;
  const hours = effectValue(buildings, TOTEM, rows);
  return Math.min(Math.max(Math.trunc(hours * 3600), base), g.OFFLINE_CAP_TOTEM_SEC);
}

/** 升级上限：议事堂自身用表 maxLevel；其余建筑受议事堂等级约束（docs/05 §2） */
export function upgradeCap(buildings: BuildingState[], buildingId: number, rows: BuildingRow[]): number {
  const row = rows.find(r => r.buildingId === buildingId);
  if (!row) return 0;
  if (buildingId === HALL) return row.maxLevel;
  return Math.min(row.maxLevel, levelOf(buildings, HALL));
}
