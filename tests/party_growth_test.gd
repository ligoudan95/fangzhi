## doc: 01 §144 / 04 §2-§4 / 16 §2（收服即入队）
## 阵伍与成长会话集成：自动上阵/上下阵/喂养/突破/出战组队（真实资质+性格）
extends GdUnitTestSuite

const SAVE_DIR: String = "user://save_party_test/"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.dir_exists("save_party_test"):
		for f in dir.get_files_at("save_party_test"):
			dir.remove("save_party_test/%s" % f)
		dir.remove("save_party_test")


func _make_session() -> Node:
	var save_svc: Node = load("res://scripts/infra/save_service.gd").new()
	save_svc.set_base_dir(SAVE_DIR)
	var session: Node = load("res://scripts/view/game_session.gd").new(save_svc)
	add_child(session)
	session.new_game(1000000, 424242)
	return session


func test_capture_auto_joins_party() -> void:
	var session := _make_session()
	session.on_pet_captured(1003)
	assert_int(session.party().size()).is_equal(1)
	var detail: Dictionary = session.get_pet_detail(1)
	assert_bool(bool(detail.inParty)).is_true()


func test_toggle_party_cap() -> void:
	var session := _make_session()
	session.on_pet_captured(1003)
	session.on_pet_captured(1001)
	session.on_pet_captured(1005)
	session.on_pet_captured(1009)  # 第 4 只不自动入队
	assert_int(session.party().size()).is_equal(3)
	var full: Dictionary = session.toggle_party(4)
	assert_bool(bool(full.ok)).is_false()
	# 下阵再上阵
	assert_bool(bool(session.toggle_party(1).ok)).is_true()
	assert_int(session.party().size()).is_equal(2)
	assert_bool(bool(session.toggle_party(4).ok)).is_true()
	assert_int(session.party().size()).is_equal(3)


func test_feed_and_breakthrough_flow() -> void:
	var session := _make_session()
	session.on_pet_captured(1003)
	session.data.player.cultivation = 2000
	# 喂到 15 级（帽）：1→14 级共 14 次，50+60+...+180 = 1610
	var feeds := 0
	for i in 14:
		var r: Dictionary = session.feed_pet(1)
		if not bool(r.ok):
			break
		feeds += 1
	assert_int(feeds).is_equal(14)
	assert_int(int(session.data.pets[0].level)).is_equal(15)
	assert_int(int(session.data.player.cultivation)).is_equal(2000 - 1610)
	# 帽上再喂失败
	assert_bool(bool(session.feed_pet(1).ok)).is_false()
	# 突破：需 500 修为（剩余 200）
	var brk: Dictionary = session.breakthrough_pet(1)
	assert_bool(bool(brk.ok)).is_false()
	assert_str(String(brk.reason)).contains("修为不足")
	session.data.player.cultivation += 500
	brk = session.breakthrough_pet(1)
	assert_bool(bool(brk.ok)).is_true()
	assert_int(int(session.data.pets[0].realmBreaks)).is_equal(1)


func test_battle_team_uses_party_with_real_aptitudes() -> void:
	var session := _make_session()
	# 空阵伍 → 序章演示三兽整队
	var demo: Array = session.build_battle_team()
	assert_int(demo.size()).is_equal(3)
	assert_int(int(demo[0].petId)).is_equal(1001)
	assert_int(int(demo[0].level)).is_equal(12)
	assert_int(int(demo[0].apts.atk)).is_equal(900)
	# 捕捉入队（敌 lv4 野性等级）→ 玩家宠在前 + 借兽补位至 3
	session.on_pet_captured(1003, 4)
	var team: Array = session.build_battle_team()
	assert_int(team.size()).is_equal(3)
	assert_int(int(team[0].petId)).is_equal(1003)
	assert_int(int(team[0].level)).is_equal(4)
	assert_int(int(team[1].petId)).is_equal(1001)
	var uniform := (
		int(team[0].apts.atk) == int(team[0].apts.def)
		and int(team[0].apts.def) == int(team[0].apts.hp)
		and int(team[0].apts.hp) == int(team[0].apts.spd)
		and int(team[0].apts.spd) == int(team[0].apts.mag)
	)
	assert_bool(uniform).is_false()  # 五维独立 roll，几乎不可能全等
	# 同种子重展开一致（确定性）
	var team2: Array = session.build_battle_team()
	assert_int(int(team2[0].apts.atk)).is_equal(int(team[0].apts.atk))
	# 集齐三兽 → 无补位，全玩家宠
	session.on_pet_captured(1001, 4)
	session.on_pet_captured(1005, 4)
	var team3: Array = session.build_battle_team()
	assert_int(team3.size()).is_equal(3)
	assert_int(int(team3[2].petId)).is_equal(1005)


func test_nature_modifiers_change_stats() -> void:
	# 性格修正并入偏移项后属性应与无修正不同（引擎 natureMods 通道冒烟）
	var session := _make_session()
	var mods: Dictionary = PetIndividuality.nature_modifiers("凶猛")
	assert_float(float(mods.atk)).is_equal(0.08)
	var plain := BattleStats.compute_stats(
		1,
		{"hp": 0.0, "atk": 0.0, "def": 0.0, "spd": 0.0, "mag": 0.0, "res": 0.0},
		12,
		{"atk": 900, "def": 900, "hp": 900, "spd": 900, "mag": 900},
		0,
		session._g()
	)
	var fierce := BattleStats.compute_stats(
		1,
		{"hp": 0.0, "atk": 0.08, "def": -0.05, "spd": 0.0, "mag": 0.0, "res": 0.0},
		12,
		{"atk": 900, "def": 900, "hp": 900, "spd": 900, "mag": 900},
		0,
		session._g()
	)
	assert_int(int(fierce.atk)).is_greater(int(plain.atk))
	assert_int(int(fierce.def)).is_less(int(plain.def))
