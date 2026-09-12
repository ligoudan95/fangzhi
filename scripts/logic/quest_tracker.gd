## doc: 16 §4 / 09 §3
## 任务/教学推进器（GDScript 镜像）——与 TS 基准 src/logic/questTracker.ts 逐行对齐。
## 纯函数：add_progress 累计进度事件（计数器持久于 state.counters）并按需完成激活节点；
## goalType=0 剧情由 advance_story 显式跳过；完成目标后连锁跳过其后剧情节点（含跨章首节点）；
## 章节耗尽进入下一章 order=1。进度持久化于 player.quests。
class_name QuestTracker
extends RefCounted


static func create_state() -> Dictionary:
	return {"chapterId": 0, "order": 1, "completed": {}, "counters": {}, "claimedXiu": 0}


static func active_quest(state: Dictionary, quests: Array) -> Dictionary:
	for q in quests:
		if int(q.chapterId) == int(state.chapterId) and int(q.order) == int(state.order):
			return q
	return {}


## 推进到下一节点；章节耗尽则进入下一章 order=1
static func _bump(state: Dictionary, quests: Array) -> void:
	state.order = int(state.order) + 1
	if active_quest(state, quests).is_empty():
		state.chapterId = int(state.chapterId) + 1
		state.order = 1


static func _complete_node(state: Dictionary, row: Dictionary) -> void:
	state.completed[str(int(row.questId))] = true
	state.claimedXiu = int(state.claimedXiu) + int(row.rewardXiu)


## 跳过当前位置起的连续剧情节点（goalType=0）
static func _skip_story(state: Dictionary, quests: Array) -> Array:
	var done: Array = []
	var active := active_quest(state, quests)
	while not active.is_empty() and int(active.goalType) == 0:
		_complete_node(state, active)
		done.append(active)
		_bump(state, quests)
		active = active_quest(state, quests)
	return done


static func _clone_state(state: Dictionary) -> Dictionary:
	return {
		"chapterId": int(state.chapterId),
		"order": int(state.order),
		"completed": state.completed.duplicate(),
		"counters": state.counters.duplicate(),
		"claimedXiu": int(state.claimedXiu),
	}


static func advance_story(state: Dictionary, quests: Array) -> Dictionary:
	var next := _clone_state(state)
	var done := _skip_story(next, quests)
	return {"state": next, "done": done}


## 累计进度并尝试完成激活节点：计数器双轨累计（类型总量/具体目标），
## targetId=0 的节点读类型总量，否则读具体目标计数；达到 count 即完成并连锁跳过剧情。
static func add_progress(
	state: Dictionary, goal_type: int, target_id: int, amount: int, quests: Array
) -> Dictionary:
	var next := _clone_state(state)
	if goal_type <= 0 or amount <= 0:
		return {"state": next, "done": [], "progressed": false}
	var type_key := "g%d" % goal_type
	next.counters[type_key] = int(next.counters.get(type_key, 0)) + amount
	var specific_key := "g%d:t%d" % [goal_type, target_id]
	next.counters[specific_key] = int(next.counters.get(specific_key, 0)) + amount

	var active := active_quest(next, quests)
	if active.is_empty() or int(active.goalType) != goal_type:
		return {"state": next, "done": [], "progressed": false}
	var effective := 0
	if int(active.targetId) == 0:
		effective = int(next.counters.get(type_key, 0))
	else:
		effective = int(next.counters.get("g%d:t%d" % [goal_type, int(active.targetId)], 0))
	if effective < int(active.count):
		return {"state": next, "done": [], "progressed": false}
	_complete_node(next, active)
	_bump(next, quests)
	var done := [active]
	done.append_array(_skip_story(next, quests))
	return {"state": next, "done": done, "progressed": true}
