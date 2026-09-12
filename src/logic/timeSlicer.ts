/**
 * UTC 时间切片（TS 基准）——与 scripts/logic/utc_time_slicer.gd 逐行镜像（docs/15 §1）。
 * tick=300s；四季每季 432000s；纪元前钳制为第 0 季。
 */

export const TICK_SEC = 300;
export const SEASON_SEC = 432000;

export function seasonIndex(utcSec: number, epochSec: number): number {
  const rel = utcSec - epochSec;
  if (rel < 0) return 0;
  return Math.floor(rel / SEASON_SEC);
}

export function seasonOfYear(utcSec: number, epochSec: number): number {
  return seasonIndex(utcSec, epochSec) % 4;
}

export function nextTickBoundary(utcSec: number, epochSec: number): number {
  const rel = utcSec - epochSec;
  const k = Math.floor(rel / TICK_SEC) + 1;
  return epochSec + k * TICK_SEC;
}

export function nextSeasonBoundary(utcSec: number, epochSec: number): number {
  const rel = utcSec - epochSec;
  if (rel < 0) return epochSec;
  const k = Math.floor(rel / SEASON_SEC) + 1;
  return epochSec + k * SEASON_SEC;
}

export interface TimeSlice { start: number; end: number; season: number }

export function sliceRange(startUtc: number, endUtc: number, epochSec: number): TimeSlice[] {
  const slices: TimeSlice[] = [];
  if (endUtc <= startUtc) return slices;
  let cursor = startUtc;
  while (cursor < endUtc) {
    const boundary = Math.min(nextTickBoundary(cursor, epochSec), nextSeasonBoundary(cursor, epochSec), endUtc);
    slices.push({ start: cursor, end: boundary, season: seasonOfYear(cursor, epochSec) });
    cursor = boundary;
  }
  return slices;
}
