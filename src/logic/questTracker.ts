/**
 * 任务/教学推进器（TS 基准，docs/16 §4 / docs/09 §3）——纯函数：
 * add_progress 累计进度事件（计数器持久于 state.counters）并按需完成当前激活节点；
 * goalType=0（剧情）由 advance_story 显式跳过；完成目标后连锁跳过其后剧情节点（含跨章首节点）；
 * 章节耗尽进入下一章 order=1。进度持久化于 player.quests。
 */
export interface QuestRow {
  questId: number; chapterId: number; order: number; nodeType: number;
  title: string; goalType: number; targetId: number; count: number; rewardXiu: number;
}

export interface QuestState {
  chapterId: number;
  order: number;            // 当前激活节点（从 1 起）
  completed: Record<number, true>;
  counters: Record<string, number>;  // "g<goal>" 类型累计 / "g<goal>:t<target>" 具体累计
  claimedXiu: number;       // 已领取修为累计（调用方入账 cultivation）
}

export function createQuestState(): QuestState {
  return { chapterId: 0, order: 1, completed: {}, counters: {}, claimedXiu: 0 };
}

export function activeQuest(state: QuestState, quests: QuestRow[]): QuestRow | null {
  return quests.find(q => q.chapterId === state.chapterId && q.order === state.order) ?? null;
}

/** 推进到下一节点；章节耗尽则进入下一章 order=1 */
function bump(state: QuestState, quests: QuestRow[]): void {
  state.order += 1;
  if (activeQuest(state, quests) === null) {
    state.chapterId += 1;
    state.order = 1;
  }
}

function completeNode(state: QuestState, row: QuestRow): void {
  state.completed[row.questId] = true;
  state.claimedXiu += row.rewardXiu;
}

/** 跳过当前位置起的连续剧情节点（goalType=0） */
function skipStory(state: QuestState, quests: QuestRow[]): QuestRow[] {
  const done: QuestRow[] = [];
  let active = activeQuest(state, quests);
  while (active && active.goalType === 0) {
    completeNode(state, active);
    done.push(active);
    bump(state, quests);
    active = activeQuest(state, quests);
  }
  return done;
}

export function advanceStory(state: QuestState, quests: QuestRow[]): { state: QuestState; done: QuestRow[] } {
  const next = cloneState(state);
  const done = skipStory(next, quests);
  return { state: next, done };
}

function cloneState(state: QuestState): QuestState {
  return {
    chapterId: state.chapterId, order: state.order,
    completed: { ...state.completed }, counters: { ...state.counters },
    claimedXiu: state.claimedXiu,
  };
}

/**
 * 累计进度并尝试完成当前激活节点：
 * - 计数器双轨累计（类型总量 g<goal> + 具体 g<goal>:t<target>），跨节点持续累加；
 * - 激活节点 goalType 不匹配 → 计数器保留、节点不动；
 * - targetId=0 的节点读类型总量，否则读具体目标计数；达到 count 即完成并连锁跳过剧情。
 */
export function addProgress(
  state: QuestState, goalType: number, targetId: number, amount: number, quests: QuestRow[],
): { state: QuestState; done: QuestRow[]; progressed: boolean } {
  const next = cloneState(state);
  if (goalType <= 0 || amount <= 0) return { state: next, done: [], progressed: false };
  // 所有章节完成（activeQuest 为 null）后停止计数，防无界增长
  if (activeQuest(next, quests) === null) return { state: next, done: [], progressed: false };
  const typeKey = `g${goalType}`;
  next.counters[typeKey] = (next.counters[typeKey] ?? 0) + amount;
  const specificKey = `g${goalType}:t${targetId}`;
  next.counters[specificKey] = (next.counters[specificKey] ?? 0) + amount;

  const active = activeQuest(next, quests);
  if (!active || active.goalType !== goalType) {
    return { state: next, done: [], progressed: false };
  }
  const effective = active.targetId === 0
    ? next.counters[typeKey] ?? 0
    : next.counters[`g${goalType}:t${active.targetId}`] ?? 0;
  if (effective < active.count) {
    return { state: next, done: [], progressed: false };
  }
  completeNode(next, active);
  bump(next, quests);
  const done = [active, ...skipStory(next, quests)];
  return { state: next, done, progressed: true };
}
