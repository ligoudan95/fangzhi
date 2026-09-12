## doc: 03 §2 / 13 §6
## 战斗装配——JSON 表 → BattleConfig（cfg：g/pets/skills/buffs/skillPool）、
## 构造战斗单位输入、读取敌人组。与 TS 基准 src/config/load.ts 逐行对齐；
## 自持 FileAccess（battle 层不 import 节点，headless 可跑）。
class_name BattleSetup
extends RefCounted


## 从目录加载全部 JSON 表（{表名: 行数组或字典}）；dir 形如 res://resources/config/
static func load_tables(dir: String) -> Dictionary:
	var tables: Dictionary = {}
	var d := DirAccess.open(dir)
	if d == null:
		push_error("BattleSetup: 打不开表目录 %s" % dir)
		return tables
	d.list_dir_begin()
	var file_name := d.get_next()
	while file_name != "":
		if file_name.get_extension() == "json":
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(dir.path_join(file_name))
			)
			if parsed != null:
				tables[file_name.get_basename()] = parsed
		file_name = d.get_next()
	d.list_dir_end()
	return tables


## 组装 BattleConfig：{g, pets{id:row}, skills{id:row}, buffs{id:row}, skillPool{petId:[按槽位]}}
static func build_cfg(tables: Dictionary) -> Dictionary:
	var pets: Dictionary = {}
	for p in tables.get("PetBase", []):
		pets[int(p.petId)] = p
	var skills: Dictionary = {}
	for s in tables.get("SkillConfig", []):
		skills[int(s.skillId)] = s
	var buffs: Dictionary = {}
	for b in tables.get("BuffConfig", []):
		buffs[int(b.buffId)] = b
	var pool: Dictionary = {}
	for r in tables.get("PetSkillPool", []):
		var key := int(r.petId)
		var arr: Array = pool.get(key, [])
		var slot := int(r.slot)
		while arr.size() <= slot:
			arr.append({})
		arr[slot] = {"skillId": int(r.skillId), "learnLv": int(r.learnLv)}
		pool[key] = arr
	return {
		"g": tables.get("GlobalConst", {}),
		"pets": pets,
		"skills": skills,
		"buffs": buffs,
		"skillPool": pool
	}


## 从种族表构造战斗单位输入（资质统一值；资质 roll 后续版本接入）
static func make_pet_input(
	cfg: Dictionary, pet_id: int, level: int, apt: int, realm_breaks: int, opts: Dictionary = {}
) -> Dictionary:
	var apts := {"atk": apt, "def": apt, "hp": apt, "spd": apt, "mag": apt}
	var skill_ids: Array = []
	for entry in cfg.skillPool.get(pet_id, []):
		if not entry.is_empty() and int(entry.learnLv) <= level:
			skill_ids.append(int(entry.skillId))
	var input := {
		"petId": pet_id,
		"level": level,
		"apts": apts,
		"realmBreaks": realm_breaks,
		"skillIds": skill_ids,
	}
	if opts.has("captureable"):
		input["captureable"] = opts["captureable"]
	if opts.has("strategy"):
		input["strategy"] = opts["strategy"]
	return input


## 读取敌人组（EnemyGroup 表）：按 groupId 过滤、slot 升序，全部可捕捉
static func group_inputs(tables: Dictionary, cfg: Dictionary, group_id: int) -> Array:
	var rows: Array = []
	for r in tables.get("EnemyGroup", []):
		if int(r.groupId) == group_id:
			rows.append(r)
	rows.sort_custom(_slot_cmp)
	var res: Array = []
	for r in rows:
		res.append(
			make_pet_input(
				cfg,
				int(r.petId),
				int(r.level),
				int(r.apt),
				0,
				{"captureable": true, "strategy": String(r.strategy)}
			)
		)
	return res


static func _slot_cmp(a: Dictionary, b: Dictionary) -> bool:
	return int(a.slot) < int(b.slot)


## 装备掉落配置（08 M3）：装备四表 → {rules, equipBase, affixes, qualities}
static func build_equip_config(tables: Dictionary) -> Dictionary:
	var rules := {}
	for r in tables.get("DropRule", []):
		rules[int(r.dropId)] = {
			"dropId": int(r.dropId),
			"source": int(r.source),
			"weights":
			[
				float(r.wWhite),
				float(r.wGreen),
				float(r.wBlue),
				float(r.wPurple),
				float(r.wOrange),
				float(r.wRed),
			],
			"luckApply": bool(r.luckApply),
			"pityQuality": int(r.pityQuality),
			"pityCount": int(r.pityCount),
			"pityUnit": String(r.pityUnit),
			"equipLvMode": String(r.equipLvMode),
			"equipLvOffsetMin": int(r.equipLvOffsetMin),
			"equipLvOffsetMax": int(r.equipLvOffsetMax),
		}
	var qualities := {}
	for q in tables.get("EquipQuality", []):
		qualities[int(q.qualityId)] = {
			"qualityId": int(q.qualityId),
			"affixMin": int(q.affixMin),
			"affixMax": int(q.affixMax),
			"rareForLuck": bool(q.rareForLuck),
			"unidentified": bool(q.unidentified),
			"requiredGroups": q.requiredGroups,
		}
	return {
		"rules": rules,
		"equipBase": tables.get("EquipBase", []),
		"affixes": tables.get("AffixPool", []),
		"qualities": qualities,
	}
