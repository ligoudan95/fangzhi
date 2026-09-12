/** UTC 时间切片 TS 基准（docs/15 §1）——与 tests/time_slicer_test.gd 同字面量 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { seasonIndex, seasonOfYear, nextTickBoundary, nextSeasonBoundary, sliceRange } from '../src/logic/timeSlicer.ts';

const EPOCH = 0;

test('季节序号与循环', () => {
  assert.equal(seasonIndex(-100, EPOCH), 0);
  assert.equal(seasonIndex(431999, EPOCH), 0);
  assert.equal(seasonIndex(432000, EPOCH), 1);
  assert.equal(seasonOfYear(432000, EPOCH), 1);
  assert.equal(seasonOfYear(4 * 432000 + 5, EPOCH), 0);
});

test('边界：tick 与季', () => {
  assert.equal(nextTickBoundary(300, EPOCH), 600);
  assert.equal(nextTickBoundary(299, EPOCH), 300);
  assert.equal(nextSeasonBoundary(-100, EPOCH), 0);
  assert.equal(nextSeasonBoundary(432000, EPOCH), 864000);
});

test('切片：跨季按季边界分段', () => {
  const slices = sliceRange(431900, 432400, EPOCH);
  assert.equal(slices.length, 3);
  assert.deepEqual(slices.map(s => s.end), [432000, 432300, 432400]);
  assert.deepEqual(slices.map(s => s.season), [0, 1, 1]);
});

test('切片：非法区间与纪元偏移', () => {
  assert.equal(sliceRange(600, 600, EPOCH).length, 0);
  assert.equal(sliceRange(700, 600, EPOCH).length, 0);
  const offset = sliceRange(1000, 1700, 1000);
  assert.equal(offset.length, 3);
  assert.deepEqual(offset.map(s => s.end), [1300, 1600, 1700]);
  assert.equal(nextTickBoundary(999, 1000), 1000);
});
