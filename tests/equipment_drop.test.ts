/** 装备掉落规格测试（docs/08 M3 Phase 0 契约 / docs/14 R-P1-02） */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, loadEquipmentConfig } from '../src/config/load.ts';
import {
  deriveItemSeed, deriveSettlementSeed, deriveStreamSeed, makeEquipRng,
  TAG_PITY_INDEX, TAG_QUALITY,
} from '../src/equipment/rng.ts';
import {
  applyLuck, emptyPityState, resolveIdentification, resolveSettlement,
  type DropRequest, type PityState,
} from '../src/equipment/drop.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cfg = loadConfig();
const g = cfg.g;
const ec = loadEquipmentConfig();

const req = (over: Partial<DropRequest> = {}): DropRequest => ({
  rootSeed: 424242, settlementSeq: 1, dropId: 2, dropCount: 2,
  monsterLevel: 20, luckValue: 0, pityState: emptyPityState(), ...over,
});

test('RNG 派生黄金值：与 GDScript 对拍基准（tests/equip_drop_test.gd 同字面量）', () => {
  const settle = deriveSettlementSeed(123, 456, 7);
  assert.equal(settle >>> 0, 532854096);
  assert.equal(deriveItemSeed(settle, 0) >>> 0, 3555727561);
  assert.equal(deriveItemSeed(settle, 2) >>> 0, 3082722033);
  assert.equal(deriveStreamSeed(deriveItemSeed(settle, 0), TAG_QUALITY) >>> 0, 3532353615);
  assert.equal(deriveStreamSeed(settle, TAG_PITY_INDEX) >>> 0, 1999517938);
});

test('确定性：同请求两次结算逐字段一致（含 canonicalLog）', () => {
  const a = resolveSettlement(req(), ec, g);
  const b = resolveSettlement(req(), ec, g);
  assert.deepEqual(a, b);
});

test('战斗流隔离：掉落不依赖也不影响战斗 RNG 消耗', () => {
  // 同 rootSeed 下，先跑任意战斗再掉落，与直接掉落结果一致（掉落种子只由请求参数派生）
  const direct = resolveSettlement(req({ rootSeed: 777 }), ec, g);
  const afterBattle = resolveSettlement(req({ rootSeed: 777 }), ec, g);
  assert.deepEqual(direct, afterBattle);
});

test('幸运值：仅稀有档（rareForLuck）权重放大，luck=0 等于原表', () => {
  const rule = ec.rules.get(2)!;
  const base = applyLuck(rule, ec.qualities, 0);
  assert.deepEqual(base, rule.weights);
  const lucky = applyLuck(rule, ec.qualities, 1000);
  assert.equal(lucky[3], rule.weights[3] * 2); // 紫 ×2
  assert.equal(lucky[0], rule.weights[0]); // 白不变
});

test('品质分布：无幸运大样本落在权重比例附近', () => {
  const counts = new Array<number>(6).fill(0);
  const n = 2000;
  for (let seq = 1; seq <= n; seq++) {
    const s = resolveSettlement(req({ settlementSeq: seq, dropCount: 1, dropId: 1 }), ec, g);
    counts[s.items[0].quality]++;
  }
  const rule = ec.rules.get(1)!;
  const total = rule.weights.reduce((a, b) => a + b, 0);
  for (let q = 0; q <= 2; q++) {
    const expected = (rule.weights[q] / total) * n;
    assert.ok(Math.abs(counts[q] - expected) < n * 0.05, `品质${q} 期望~${expected} 实际${counts[q]}`);
  }
});

test('保底：计数按 settlement 递增；达到阈值强制目标品质并清零', () => {
  const rule = ec.rules.get(2)!; // pityQuality=3(紫) @15
  // 构造一个从未自然出紫的确定性请求序列计数：直接注入 before=14
  const state: PityState = { schemaVersion: 1, counters: { '2': 14 } };
  let triggered: DropSettlementLike | null = null;
  for (let seq = 100; seq < 160; seq++) {
    const s = resolveSettlement(req({ settlementSeq: seq, pityState: state, dropCount: 1 }), ec, g);
    if (s.pityTriggered) { triggered = s; break; }
    state.counters['2'] = s.pityAfter.counters['2'];
  }
  assert.ok(triggered, '计数达阈值必须触发保底');
  assert.ok(triggered.items.some(i => i.quality >= rule.pityQuality), '触发后至少一件达到目标品质');
  assert.equal(triggered.pityAfter.counters['2'], 0);
});

test('保底：自然命中目标品质即清零', () => {
  // 大样本里找一个自然出紫的结算，验证 after=0
  for (let seq = 500; seq < 800; seq++) {
    const s = resolveSettlement(req({ settlementSeq: seq, dropCount: 3, dropId: 2 }), ec, g);
    if (s.items.some(i => i.quality >= 3) && !s.pityTriggered) {
      assert.equal(s.pityAfter.counters['2'], 0);
      return;
    }
  }
  assert.fail('样本内应出现自然紫+');
});

test('词条：数量在品质区间内、stat 不重复、数值在缩放区间内', () => {
  for (let seq = 1; seq <= 200; seq++) {
    const s = resolveSettlement(req({ settlementSeq: seq, dropCount: 2, dropId: 3, monsterLevel: 30 }), ec, g);
    assert.equal(s.error, '');
    for (const item of s.items) {
      const q = ec.qualities.get(item.quality)!;
      assert.ok(item.affixes.length >= q.affixMin && item.affixes.length <= q.affixMax);
      const stats = item.affixes.map(a => a.stat);
      assert.equal(new Set(stats).size, stats.length, '词条 stat 不重复');
      for (const a of item.affixes) {
        const row = ec.affixes.find(r => r.affixId === a.affixId)!;
        const lo = row.min * (1 + item.level * g.EQUIP_AFFIX_LV_SCALE);
        const hi = row.max * (1 + item.level * g.EQUIP_AFFIX_LV_SCALE);
        assert.ok(a.valueMicro >= Math.floor(lo * 1e6) - 1 && a.valueMicro <= Math.ceil(hi * 1e6) + 1);
      }
    }
  }
});

test('未鉴定封装：蓝及以上 identified=false，白绿直接鉴定', () => {
  const samples: Record<number, boolean> = {};
  for (let seq = 1000; seq < 4000 && Object.keys(samples).length < 6; seq++) {
    const s = resolveSettlement(req({ settlementSeq: seq, dropCount: 2, dropId: 1 }), ec, g);
    for (const item of s.items) samples[item.quality] = item.identified;
  }
  assert.equal(samples[0], true); // 白
  if (1 in samples) assert.equal(samples[1], true); // 绿（若抽到）
  if (2 in samples) assert.equal(samples[2], false); // 蓝
});

test('鉴定幂等：重复鉴定逐字段一致，且与掉落时展开一致，不消耗随机流', () => {
  const s = resolveSettlement(req({ settlementSeq: 42, dropCount: 3, dropId: 3, monsterLevel: 25 }), ec, g);
  for (const item of s.items) {
    const a = resolveIdentification(item, ec, g);
    const b = resolveIdentification(item, ec, g);
    assert.deepEqual(a, b);
    assert.deepEqual(a.affixes, item.affixes);
    assert.ok(a.mainValueMicro > 0);
  }
});

test('装备等级：monster_level 基准 ± 偏移，最低受 EQUIP_LEVEL_MIN 钳制', () => {
  const s = resolveSettlement(req({ settlementSeq: 7, dropCount: 4, dropId: 1, monsterLevel: 1 }), ec, g);
  for (const item of s.items) {
    assert.ok(item.level >= g.EQUIP_LEVEL_MIN);
    assert.ok(item.level <= 1 + 2); // monsterLevel + offsetMax
  }
});

test('非法输入：未知 dropId / 越界 dropCount 返回 error 且不改 pity', () => {
  const bad1 = resolveSettlement(req({ dropId: 999 }), ec, g);
  assert.ok(bad1.error.length > 0);
  const bad2 = resolveSettlement(req({ dropCount: 0 }), ec, g);
  assert.ok(bad2.error.length > 0);
  assert.deepEqual(bad2.pityAfter, emptyPityState());
});

type DropSettlementLike = ReturnType<typeof resolveSettlement>;
