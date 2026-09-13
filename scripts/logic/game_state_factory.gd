## doc: 15 §3.2
## 新档状态工厂（纯逻辑）：按 schema v1 生成完整默认 data；所有游标同一 now，五条 RNG 流独立派生。
class_name GameStateFactory
extends RefCounted

const RNG_STREAM_TAGS: Array[int] = [1, 2, 3, 4, 5]


static func create_new(now_utc: int, root_seed: int) -> Dictionary:
	var streams: Array = []
	for tag in RNG_STREAM_TAGS:
		(
			streams
			. append(
				{
					"streamId": tag,
					"seed": EquipDropRng.derive_stream_seed(root_seed, tag),
					"state": EquipDropRng.derive_stream_seed(root_seed, tag),
					"drawCount": 0,
				}
			)
		)
	return {
		"meta":
		{
			"saveId": "%d_%d" % [now_utc, root_seed],
			"createdAtUtcSec": now_utc,
			"updatedAtUtcSec": now_utc,
			"lastObservedUtcSec": now_utc,
			"clockRollbackCount": 0,
		},
		"player":
		{"realmId": 1, "realmLayer": 0, "cultivation": 0, "quests": QuestTracker.create_state()},
		"wallet": {"beastShell": 0, "spiritCrystal": 0, "totemEmblem": 0},
		"pets": [],
		"equipment": {"items": [], "pityCounters": {}, "appliedSettlementIds": []},
		"village":
		{
			"population": 0,
			"buildings": [],
			"fields": [],
			"mineJobs": [],
			"recipeJobs": [],
			"petConditions": [],
			"storage": [],
		},
		"settlement":
		{
			"cursors":
			{
				"cultivationUtcSec": now_utc,
				"patrolUtcSec": now_utc,
				"villageProductionUtcSec": now_utc,
				"craftUtcSec": now_utc,
				"beastTideUtcSec": now_utc,
			},
			"pendingReports": {},
		},
		"rng": {"rootSeed": root_seed, "streams": streams},
	}
