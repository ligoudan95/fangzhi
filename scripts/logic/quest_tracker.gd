## doc: 16 §4 / 09 §3
## 任务/教学推进器（GDScript 镜像）——与 TS 基准 src/logic/questTracker.ts 逐行对齐。
## 纯函数：goalType=0 剧情由 advance_story 显式跳过；目标节点由 apply_progress 消费事件；
## 章节耗尽进入下一章 order=1；完成目标后连锁跳过其后剧情节点（含跨章首节点）。
class_name QuestTracker
extends RefCounted


static func create_state() -> Dictionary:
	return {"chapterId": 0, "order": 1, "completed": {}, "claimedXiu": 0}


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
	state.completed[int(row.questId)] = true
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


static func advance_story(state: Dictionary, quests: Array) -> Dictionary:
	var next := {
		"chapterId": int(state.chapterId),
		"order": int(state.order),
		"completed": state.completed.duplicate(),
		"claimedXiu": int(state.claimedXiu),
	}
	var done := _skip_story(next, quests)
	return {"state": next, "done": done}


## 应用进度事件：goalType/targetId 匹配（0=任意）且 amount ≥ count 才生效；
## goalType=0 节点不接受进度事件（走 advance_story）。
static func apply_progress(
	state: Dictionary, goal_type: int, target_id: int, amount: int, quests: Array
) -> Dictionary:
	var next := {
		"chapterId": int(state.chapterId),
		"order": int(state.order),
		"completed": state.completed.duplicate(),
		"claimedXiu": int(state.claimedXiu),
	}
	var active := active_quest(next, quests)
	if active.is_empty() or int(active.goalType) == 0 or int(active.goalType) != goal_type:
		return {"state": next, "done": [], "progressed": false}
	if int(active.targetId) != 0 and int(active.targetId) != target_id:
		return {"state": next, "done": [], "progressed": false}
	if amount < int(active.count):
		return {"state": next, "done": [], "progressed": false}
	_complete_node(next, active)
	_bump(next, quests)
	var done := [active]
	done.append_array(_skip_story(next, quests))
	return {"state": next, "done": done, "progressed": true}
