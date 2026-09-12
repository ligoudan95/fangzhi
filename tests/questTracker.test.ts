/** 任务/教学推进器测试——与 tests/quest_tracker_test.gd 同口径同字面量 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  activeQuest, addProgress, advanceStory, createQuestState, type QuestRow,
} from '../src/logic/questTracker.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const quests: QuestRow[] = JSON.parse(readFileSync(join(ROOT, 'out/config/MainQuest.json'), 'utf8'));

test('初始激活序章剧情节点，advanceStory 跳过并停在目标节点', () => {
  const s = createQuestState();
  assert.equal(activeQuest(s, quests)?.questId, 1);
  const r = advanceStory(s, quests);
  assert.deepEqual(r.done.map(q => q.questId), [1]);       // 兽潮之夜（剧情）
  assert.equal(activeQuest(r.state, quests)?.questId, 2);   // 停在"守住第一波"
  assert.equal(r.state.claimedXiu, 200);
});

test('进度事件：目标/类型不匹配不推进（计数器保留）', () => {
  const s = advanceStory(createQuestState(), quests).state;   // active=守住第一波(goal1,target1)
  const wrongType = addProgress(s, 2, 1, 1, quests);
  assert.equal(wrongType.progressed, false);
  const wrongTarget = addProgress(s, 1, 99, 1, quests);
  assert.equal(wrongTarget.progressed, false);
  assert.equal(wrongTarget.state.counters['g1:t99'], 1);   // 计数器仍累计
  assert.deepEqual(wrongTarget.state.completed, s.completed);
});

test('通关序章：stage→捕捉→跨章连锁跳过第一章首剧情', () => {
  let s = advanceStory(createQuestState(), quests).state;
  s = addProgress(s, 1, 1, 1, quests).state;   // 守住第一波
  const r = addProgress(s, 2, 0, 1, quests);   // 收服第一只（任意捕捉）
  assert.equal(r.progressed, true);
  assert.deepEqual(r.done.map(q => q.questId), [3, 4]);     // 收服第一只 + 黑风林的低语（跨章连锁）
  assert.equal(r.state.chapterId, 1);
  assert.equal(activeQuest(r.state, quests)?.questId, 5);   // 藤影清剿
});

test('累计进度：捕捉同一目标分三次达成 count=3 节点', () => {
  let s = advanceStory(createQuestState(), quests).state;
  s = addProgress(s, 1, 1, 1, quests).state;      // 序章 stage
  s = addProgress(s, 2, 0, 1, quests).state;      // 序章 捕捉 → 进入第一章
  s = addProgress(s, 1, 2, 1, quests).state;      // 藤影清剿
  s = addProgress(s, 3, 0, 1, quests).state;      // 首件战利品
  s = addProgress(s, 4, 0, 1, quests).state;      // 鉴定开光
  // 木系图鉴·初（goal2, target2, count3）：分三次累计
  const r1 = addProgress(s, 2, 1003, 1, quests);
  assert.equal(r1.progressed, false);             // 1/3 未达
  const r2 = addProgress(r1.state, 2, 1003, 1, quests);
  assert.equal(r2.progressed, false);             // 2/3 未达
  const r3 = addProgress(r2.state, 2, 1003, 1, quests);
  assert.equal(r3.progressed, true);              // 3/3 达成
  assert.equal(activeQuest(r3.state, quests)?.questId, 9);   // 三兽成阵
});

test('第一章全流程走查：13 节点按序完成至域主藤皇', () => {
  let s = advanceStory(createQuestState(), quests).state;
  const events: Array<[number, number, number]> = [
    [1, 1, 1],    // 序章 stage1
    [2, 0, 1],    // 序章 捕捉
    [1, 2, 1],    // 藤影清剿 stage2
    [3, 0, 1],    // 首件战利品
    [4, 0, 1],    // 鉴定开光
    [2, 1003, 1], [2, 1003, 1], [2, 1003, 1],  // 木系图鉴·初 ×3（累计）
    [6, 0, 3],    // 三兽成阵
    [5, 0, 1],    // 播种时节（收获）
    [1, 4, 1],    // 雾深处
    [1, 5, 1],    // 老藤营地
    [1, 6, 1],    // 域主·藤皇
  ];
  for (const [goalType, targetId, amount] of events) {
    s = addProgress(s, goalType, targetId, amount, quests).state;
  }
  assert.equal(s.completed[13], true);
  assert.equal(s.chapterId, 2);
  assert.equal(activeQuest(s, quests), null);
  assert.equal(s.claimedXiu, 5400);
});

test('幂等：同事件序列两次执行状态一致', () => {
  const run = () => {
    let s = advanceStory(createQuestState(), quests).state;
    for (const e of [[1, 1, 1], [2, 0, 1], [1, 2, 1]] as const) {
      s = addProgress(s, e[0], e[1], e[2], quests).state;
    }
    return s;
  };
  assert.deepEqual(run(), run());
});
