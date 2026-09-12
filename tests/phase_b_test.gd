## doc: 26 §4（Phase B 矿场/兽潮）——与 TS 基准 tests/phaseB.test.ts 同口径
extends GdUnitTestSuite

var _tables: Dictionary = {}
var _cfg: Dictionary = {}
var _mconfig: Dictionary = {}


func before_test() -> void:
	if _tables.is_empty():
		_tables = BattleSetup.load_tables("res://resources/config/")
		_cfg = BattleSetup.build_cfg(_tables)
		var mines := {}
		for m in _tables.get("Mine", []):
			mines[int(m.mineId)] = m
		var seasons := {}
		for s in _tables.get("SeasonWeather", []):
			seasons[int(s.seasonId)] = s
		_mconfig = {
			"mines": mines,
			"seasons": seasons,
			"categoryOf": {201: 1, 202: 1, 203: 1},
			"storageRules": {1: 200},
			"g": {"SEASON_EPOCH_UTC_SEC": 0, "OFFLINE_CAP_BASE_SEC": 43200},
		}


## 矿场：浅层铁矿 1 小时 → 8 铁矿
func test_mine_shallow_iron_one_hour() -> void:
	var jobs: Array = [
		{"slotId": 1, "mineId": 1, "startedAtUtcSec": 0, "assignedPetInstanceIds": []}
	]
	var r: Dictionary = MineProduction.settle_mines(
		jobs, 0, 3600, {"beastShell": 0, "spiritCrystal": 0, "totemEmblem": 0}, [], _mconfig
	)
	var iron: int = 0
	for o in r.outputs:
		if int(o.itemId) == 201:
			iron += int(o.amount)
	assert_int(iron).is_equal(8)


## 矿场：深层矿灵晶入钱包
func test_mine_deep_crystal_to_wallet() -> void:
	var jobs: Array = [
		{"slotId": 1, "mineId": 3, "startedAtUtcSec": 0, "assignedPetInstanceIds": []}
	]
	var r: Dictionary = MineProduction.settle_mines(
		jobs, 0, 3600, {"beastShell": 0, "spiritCrystal": 10, "totemEmblem": 0}, [], _mconfig
	)
	assert_int(int(r.wallet.spiritCrystal)).is_greater(10)


## 矿场：倒流零产出
func test_mine_rollback_zero() -> void:
	var jobs: Array = [
		{"slotId": 1, "mineId": 1, "startedAtUtcSec": 0, "assignedPetInstanceIds": []}
	]
	var r: Dictionary = MineProduction.settle_mines(
		jobs, 1000, 500, {"beastShell": 0, "spiritCrystal": 0, "totemEmblem": 0}, [], _mconfig
	)
	assert_int(r.outputs.size()).is_equal(0)


## 兽潮：波次枚举 12:00/20:00 本地（UTC+8）
func test_tide_wave_boundaries() -> void:
	var waves: Array = BeastTide.wave_boundaries(0, 86400, 28800, 4)
	assert_array(waves).is_equal([14400, 43200])  # 24h 含 2 波


## 兽潮：种子确定 + 补结算报告结构
func test_tide_seed_and_settle() -> void:
	assert_int(BeastTide.wave_seed(42, 14400)).is_equal(BeastTide.wave_seed(42, 14400))
	var team: Array = BattleSetup.group_inputs(_tables, _cfg, 2)
	var g: Dictionary = _tables.get("GlobalConst", {})
	var r: Dictionary = BeastTide.settle_missed(0, 86400, 28800, 42, team, _tables, _cfg, g)
	assert_int(r.waves.size()).is_equal(2)  # 24h 窗口 2 波
	assert_int(int(r.settledCount)).is_equal(2)  # 24h 窗口 2 波
	for w in r.waves:
		assert_bool(["victory", "defeat", "timeout"].has(String(w.outcome))).is_true()
