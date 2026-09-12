## doc: 16 §4 / 09 §3
## 任务/教学推进器测试——与 TS 基准 tests/questTracker.test.ts 同口径同字面量。
extends GdUnitTestSuite

var _quests: Array = []


func before_test() -> void:
	if _quests.is_empty():
		var tables := BattleSetup.load_tables("res://resources/config/")
		_quests = tables.get("MainQuest", [])


## 初始激活序章剧情节点，advance_story 跳过并停在目标节点
func test_advance_story_skips_to_goal_node() -> void:
	var s: Dictionary = QuestTracker.create_state()
	assert_int(int(QuestTracker.active_quest(s, _quests).questId)).is_equal(1)
	var r: Dictionary = QuestTracker.advance_story(s, _quests)
	var done_ids: Array = []
	for q in r.done:
		done_ids.append(int(q.questId))
	assert_array(done_ids).is_equal([1])
	assert_int(int(QuestTracker.active_quest(r.state, _quests).questId)).is_equal(2)
	assert_int(int(r.state.claimedXiu)).is_equal(200)


## 进度事件：目标/类型不匹配不推进
func test_progress_mismatch_no_advance() -> void:
	var s: Dictionary = QuestTracker.advance_story(QuestTracker.create_state(), _quests).state
	var wrong_type: Dictionary = QuestTracker.apply_progress(s, 2, 1, 1, _quests)
	assert_bool(wrong_type.progressed).is_false()
	var wrong_target: Dictionary = QuestTracker.apply_progress(s, 1, 99, 1, _quests)
	assert_bool(wrong_target.progressed).is_false()


## 通关序章：stage→捕捉→跨章连锁跳过第一章首剧情
func test_prologue_chain_into_chapter_one() -> void:
	var s: Dictionary = QuestTracker.advance_story(QuestTracker.create_state(), _quests).state
	s = QuestTracker.apply_progress(s, 1, 1, 1, _quests).state
	var r: Dictionary = QuestTracker.apply_progress(s, 2, 0, 1, _quests)
	assert_bool(r.progressed).is_true()
	var done_ids: Array = []
	for q in r.done:
		done_ids.append(int(q.questId))
	assert_array(done_ids).is_equal([3, 4])
	assert_int(int(r.state.chapterId)).is_equal(1)
	assert_int(int(QuestTracker.active_quest(r.state, _quests).questId)).is_equal(5)


## 第一章全流程走查：13 节点按序完成至域主藤皇
func test_full_chapter_walkthrough() -> void:
	var s: Dictionary = QuestTracker.advance_story(QuestTracker.create_state(), _quests).state
	var events: Array = [
		[1, 1, 1],
		[2, 0, 1],
		[1, 2, 1],
		[5, 1, 1],
		[3, 0, 1],
		[4, 0, 1],
		[2, 2, 3],
		[6, 0, 3],
		[1, 4, 1],
		[1, 5, 1],
		[1, 6, 1],
	]
	for e in events:
		s = QuestTracker.apply_progress(s, int(e[0]), int(e[1]), int(e[2]), _quests).state
	assert_bool(bool(s.completed.get(13, false))).is_true()
	assert_int(int(s.chapterId)).is_equal(2)
	assert_bool(QuestTracker.active_quest(s, _quests).is_empty()).is_true()
	assert_int(int(s.claimedXiu)).is_equal(5400)


## 幂等：同事件序列两次执行状态一致
func test_walkthrough_idempotent() -> void:
	var run := func() -> Dictionary:
		var s: Dictionary = QuestTracker.advance_story(QuestTracker.create_state(), _quests).state
		for e in [[1, 1, 1], [2, 0, 1], [1, 2, 1]]:
			s = QuestTracker.apply_progress(s, int(e[0]), int(e[1]), int(e[2]), _quests).state
		return s
	var a: Dictionary = run.call()
	var b: Dictionary = run.call()
	assert_int(int(a.claimedXiu)).is_equal(int(b.claimedXiu))
	assert_int(a.completed.size()).is_equal(b.completed.size())
