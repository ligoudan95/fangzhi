## 自动生成：配置表字段元数据，勿手改。
## doc: 12-导表与数据管线 §1-§2/§7
# gdformat: disable
class_name ConfigTypes
extends RefCounted

const PRIMARY_KEYS: Dictionary = {
	"Enums": ["enumName", "value"],
	"GlobalConst": ["key"],
	"PetBase": ["petId"],
	"SkillConfig": ["skillId"],
	"PetSkillPool": ["petId", "slot"],
	"BuffConfig": ["buffId"],
	"EnemyGroup": ["groupId", "slot"],
	"StageConfig": ["stageId"],
	"DropRule": ["dropId"],
	"Crop": ["cropId"],
	"MainQuest": ["questId"],
	"EquipBase": ["equipId"],
	"AffixPool": ["affixId"],
	"EquipQuality": ["qualityId"],
	"ItemBase": ["itemId"],
	"StorageRule": ["categoryId"],
	"SeasonWeather": ["seasonId"],
	"Mine": ["mineId"],
	"Building": ["buildingId"],
	"Recipe": ["recipeId"]
}
const FIELD_TYPES: Dictionary = {
	"AffixPool": {
		"affixId": "int",
		"group": "int",
		"stat": "string",
		"rollType": "int",
		"min": "float",
		"max": "float",
		"weight": "float",
		"qualityMin": "int",
		"qualityMax": "int"
	},
	"BuffConfig": {
		"buffId": "int",
		"name": "string",
		"kind": "int",
		"modStat": "string",
		"modPct": "float",
		"modStat2": "string",
		"modPct2": "float",
		"dotPct": "float",
		"dotElement": "int",
		"markElement": "int",
		"markPct": "float",
		"ctrlRes": "float",
		"stacks": "int",
		"duration": "int",
		"captureLinked": "bool",
		"control": "int"
	},
	"Building": {
		"buildingId": "int",
		"name": "string",
		"maxLevel": "int",
		"unlockRealm": "string",
		"effectKind": "enum<BuildingEffect>",
		"effectBase": "float",
		"effectStep": "float",
		"upgradeCostKey": "string",
		"upgradeCostBase": "int",
		"upgradeCostStep": "int"
	},
	"Crop": {
		"cropId": "int",
		"name": "string",
		"seedCost": "int",
		"growMin": "int",
		"yieldN": "int",
		"outputItemId": "ref<ItemBase>",
		"outputCount": "int",
		"unlock": "string"
	},
	"DropRule": {
		"dropId": "int",
		"source": "int",
		"wWhite": "float",
		"wGreen": "float",
		"wBlue": "float",
		"wPurple": "float",
		"wOrange": "float",
		"wRed": "float",
		"luckApply": "bool",
		"pityQuality": "int",
		"pityCount": "int",
		"equipLvRule": "string",
		"pityUnit": "string",
		"equipLvMode": "string",
		"equipLvOffsetMin": "int",
		"equipLvOffsetMax": "int"
	},
	"EnemyGroup": {
		"groupId": "int",
		"slot": "int",
		"petId": "ref<PetBase>",
		"level": "int",
		"apt": "int",
		"strategy": "string"
	},
	"Enums": {
		"enumName": "string",
		"value": "int",
		"label": "string"
	},
	"EquipBase": {
		"equipId": "int",
		"slot": "int",
		"mainStat": "string",
		"baseValue": "float",
		"weight": "float"
	},
	"EquipQuality": {
		"qualityId": "int",
		"affixMin": "int",
		"affixMax": "int",
		"rareForLuck": "bool",
		"unidentified": "bool",
		"requiredGroups": "array<int>(2)"
	},
	"GlobalConst": {
		"key": "string",
		"value": "float",
		"desc": "string"
	},
	"ItemBase": {
		"itemId": "int",
		"name": "string",
		"kind": "enum<ItemKind>",
		"storageCategory": "ref<StorageRule>"
	},
	"MainQuest": {
		"questId": "int",
		"chapterId": "int",
		"order": "int",
		"nodeType": "enum<NodeType>",
		"title": "string",
		"goalType": "enum<GoalType>",
		"targetId": "int",
		"count": "int",
		"rewardXiu": "int"
	},
	"Mine": {
		"mineId": "int",
		"name": "string",
		"unlockRealm": "string",
		"ironRate": "int",
		"crystalRate": "int",
		"refinedRate": "int",
		"spiritRate": "int",
		"collapseRisk": "float"
	},
	"PetBase": {
		"petId": "int",
		"name": "string",
		"element": "int",
		"quality": "int",
		"template": "int",
		"offHp": "float",
		"offAtk": "float",
		"offDef": "float",
		"offSpd": "float",
		"offMag": "float",
		"offRes": "float",
		"aptitudes": "array<int>(10)",
		"laborPow": "int",
		"laborDex": "int",
		"laborApt": "int",
		"natures": "array<string>(4)",
		"breaks": "array<string>(5)",
		"captureNote": "string"
	},
	"PetSkillPool": {
		"petId": "ref<PetBase>",
		"slot": "int",
		"skillId": "ref<SkillConfig>",
		"learnLv": "int"
	},
	"Recipe": {
		"recipeId": "int",
		"station": "enum<Station>",
		"inputs": "string",
		"outputItemId": "ref<ItemBase>",
		"outputCount": "int",
		"durationMin": "int",
		"unlockRealm": "string"
	},
	"SeasonWeather": {
		"seasonId": "int",
		"name": "string",
		"farmMult": "float",
		"mineMult": "float",
		"beastMult": "float"
	},
	"SkillConfig": {
		"skillId": "int",
		"name": "string",
		"element": "int",
		"selector": "string",
		"effects": "array<effect>",
		"cd": "int",
		"rageGain": "int",
		"learnLv": "int",
		"isUlt": "bool"
	},
	"StageConfig": {
		"stageId": "int",
		"mapId": "int",
		"order": "int",
		"name": "string",
		"waves": "refs<EnemyGroup>",
		"dropId": "ref<DropRule>",
		"dropCount": "int",
		"power": "int",
		"captureable": "bool",
		"boss": "bool"
	},
	"StorageRule": {
		"categoryId": "int",
		"baseCap": "int"
	}
}
const ARRAY_LENGTHS: Dictionary = {
	"AffixPool": {},
	"BuffConfig": {},
	"Building": {},
	"Crop": {},
	"DropRule": {},
	"EnemyGroup": {},
	"Enums": {},
	"EquipBase": {},
	"EquipQuality": {
		"requiredGroups": 2
	},
	"GlobalConst": {},
	"ItemBase": {},
	"MainQuest": {},
	"Mine": {},
	"PetBase": {
		"aptitudes": 10,
		"natures": 4,
		"breaks": 5
	},
	"PetSkillPool": {},
	"Recipe": {},
	"SeasonWeather": {},
	"SkillConfig": {},
	"StageConfig": {},
	"StorageRule": {}
}
