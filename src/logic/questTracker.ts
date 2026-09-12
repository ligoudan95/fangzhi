/**
 * 任务/教学推进器（TS 基准，docs/16 §4 / docs/09 §3）——纯函数：
 * 按章节顺序推进；goalType=0（剧情）由 advanceStory 显式跳过，goalType>0 由
 * applyProgress 消费进度事件匹配累计；章节耗尽自动进入下一章 order=1；
 * 完成目标节点后连锁跳过其后剧情节点（含跨章首节点）。进度持久化于 player.quests。
 */
export interface QuestRow {
  questId: number; chapterId: number; order: number; nodeType: number;
  title: string; goalType: number; targetId: number; count: number; rewardXiu: number;
}

export interface QuestState {
  chapterId: number;
  order: number;            // 当前激活节点（从 1 起）
  completed: Record<number, true>;
  claimedXiu: number;       // 已领取修为累计（调用方入账 cultivation）
}

export interface ProgressEvent { goalType: number; targetId: number; amount: number }

export function createQuestState(): QuestState {
  return { chapterId: 0, order: 1, completed: {}, claimedXiu: 0 };
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

/** 跳过当前位置起的连续剧情节点（goalType=0），返回被完成节点 */
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
  const next: QuestState = { ...state, completed: { ...state.completed } };
  const done = skipStory(next, quests);
  return { state: next, done };
}

/**
 * 应用进度事件：仅当事件与当前激活节点的 goalType 匹配且 targetId 匹配（0=任意）时生效；
 * goalType=0 节点不接受进度事件（走 advanceStory）。达成后完成并连锁跳过剧情节点。
 */
export function applyProgress(
  state: QuestState, event: ProgressEvent, quests: QuestRow[],
): { state: QuestState; done: QuestRow[]; progressed: boolean } {
  const next: QuestState = { ...state, completed: { ...state.completed } };
  const active = activeQuest(next, quests);
  if (!active || active.goalType === 0 || active.goalType !== event.goalType) {
    return { state: next, done: [], progressed: false };
  }
  if (active.targetId !== 0 && active.targetId !== event.targetId) {
    return { state: next, done: [], progressed: false };
  }
  if (event.amount < active.count) {
    return { state: next, done: [], progressed: false };
  }
  completeNode(next, active);
  bump(next, quests);
  const done = [active, ...skipStory(next, quests)];
  return { state: next, done, progressed: true };
}
