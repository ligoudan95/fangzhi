/** 任务/教学推进器测试——与 tests/quest_tracker_test.gd 同口径同字面量 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  activeQuest, advanceStory, applyProgress, createQuestState, type QuestRow,
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

test('进度事件：目标/类型不匹配不推进', () => {
  const s = advanceStory(createQuestState(), quests).state;   // active=守住第一波(goal1,target1)
  const wrongType = applyProgress(s, { goalType: 2, targetId: 1, amount: 1 }, quests);
  assert.equal(wrongType.progressed, false);
  const wrongTarget = applyProgress(s, { goalType: 1, targetId: 99, amount: 1 }, quests);
  assert.equal(wrongTarget.progressed, false);
  assert.deepEqual(wrongTarget.state.completed, s.completed);
});

test('通关序章：stage→捕捉→教学节点连带剧情跳完入第一章', () => {
  let s = advanceStory(createQuestState(), quests).state;
  s = applyProgress(s, { goalType: 1, targetId: 1, amount: 1 }, quests).state;   // 守住第一波
  // 序章节点3（收服第一只，goal2）激活；完成它后序章耗尽 → 连锁进入第一章并跳过首剧情
  const r = applyProgress(s, { goalType: 2, targetId: 0, amount: 1 }, quests);
  assert.equal(r.progressed, true);
  assert.deepEqual(r.done.map(q => q.questId), [3, 4]);     // 收服第一只 + 黑风林的低语（跨章连锁）
  assert.equal(r.state.chapterId, 1);
  assert.equal(activeQuest(r.state, quests)?.questId, 5);   // 藤影清剿
});

test('第一章全流程走查：10 节点按序完成至域主藤皇', () => {
  let s = advanceStory(createQuestState(), quests).state;
  const events: Array<[number, number, number]> = [
    [1, 1, 1],    // 序章 stage1
    [2, 0, 1],    // 序章 捕捉
    // 第一章 1 已被连锁跳过；5 藤影清剿 stage2
    [1, 2, 1],
    // 6 播种时节 goal5 crop1
    [5, 1, 1],
    // 7 首件战利品 goal3
    [3, 0, 1],
    // 8 鉴定开光 goal4
    [4, 0, 1],
    // 9 木系图鉴·初 goal2×3（藤蔓妖2）
    [2, 2, 3],
    // 10 三兽成阵 goal6×3
    [6, 0, 3],
    // 11 雾深处 stage4
    [1, 4, 1],
    // 12 老藤营地 stage5
    [1, 5, 1],
    // 13 域主·藤皇 stage6
    [1, 6, 1],
  ];
  for (const [goalType, targetId, amount] of events) {
    s = applyProgress(s, { goalType, targetId, amount }, quests).state;
  }
  assert.equal(s.completed[13], true);       // 域主藤皇完成
  assert.equal(s.chapterId, 2);              // 章节耗尽进入下一章（无数据=终态）
  assert.equal(activeQuest(s, quests), null);
  assert.equal(s.claimedXiu, 5400);         // 全部 13 节点 rewardXiu 累计
});

test('幂等：同事件序列两次执行状态一致', () => {
  const run = () => {
    let s = advanceStory(createQuestState(), quests).state;
    for (const e of [[1, 1, 1], [2, 0, 1], [1, 2, 1]] as const) {
      s = applyProgress(s, { goalType: e[0], targetId: e[1], amount: e[2] }, quests).state;
    }
    return s;
  };
  assert.deepEqual(run(), run());
});
