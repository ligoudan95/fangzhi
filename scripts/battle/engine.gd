## doc: 03 全文 / 07 §5 / 13 §6
## 确定性回合制战斗引擎——与 TS 基准 src/battle/engine.ts 逐行对齐。
## 对拍红线：RNG 消耗顺序、分支顺序、日志文案、数值运算次序必须完全一致；
## 字典取值是 Variant，参与运算/推断时一律显式转型（/1000 等除法防整除）。
class_name Battle
extends RefCounted

## 五行循环相克：金克木 木克土 土克水 水克火 火克金（02 §4.3）
const BEATS: Dictionary = {1: 2, 2: 5, 5: 3, 3: 4, 4: 1}

var cfg: Dictionary
var g: Dictionary
var rng: BattleRng
var units: Array = []
var bench: Array = [[], []]
var round_num: int = 0
var log_lines: Array = []
var events: Array = []
var outcome: String = ""
var captured_pet_id: int = -1
var capture_mode: bool = false
var capture_target_uid: int = -1
var _pending_capture_actor_uid: int = -1
var _uid_seq: int = 1


func _init(
	cfg_in: Dictionary, side_a: Array, side_b: Array, seed: int, opts: Dictionary = {}
) -> void:
	cfg = cfg_in
	g = cfg_in.g
	rng = BattleRng.new(seed)
	capture_mode = bool(opts.get("capture", false))
	for i in range(mini(3, side_a.size())):
		units.append(_make_unit(side_a[i], 0))
	for i in range(3, side_a.size()):
		bench[0].append(_make_unit(side_a[i], 0))
	for i in range(mini(3, side_b.size())):
		units.append(_make_unit(side_b[i], 1))
	for i in range(3, side_b.size()):
		bench[1].append(_make_unit(side_b[i], 1))
	if capture_mode:
		for u in units:
			if int(u.side) == 1 and bool(u.captureable):
				capture_target_uid = int(u.uid)
				break


# ---------- 纯公式（可单测） ----------


static func clash(a: int, d: int, g: Dictionary) -> float:
	if int(BEATS.get(a, 0)) == d:
		return float(g.CLASH_ADV)
	if int(BEATS.get(d, 0)) == a:
		return float(g.CLASH_DIS)
	if (a == 6 and d == 7) or (a == 7 and d == 6):
		return float(g.CLASH_ADV)
	return 1.0


static func calc_damage(inp: Dictionary, roll: Dictionary, g: Dictionary) -> int:
	if not bool(roll.hit):
		return 0
	var cl := clash(int(inp.attackerElement), int(inp.defenderElement), g)
	var def_stat := float(inp.defStat)
	var mit := minf(
		def_stat / (def_stat + float(g.DEF_K) * float(inp.defenderLevel)), float(g.MIT_CAP)
	)
	var d := float(inp.atkStat) * float(inp.power) * cl * (1.0 - mit)
	if bool(roll.crit):
		d *= float(g.CRIT_DMG)
	d *= float(inp.dmgMod) * (1.0 + float(inp.markPct)) * float(roll.float)
	return maxi(1, roundi(d))


static func compute_capture_rate(inp: Dictionary, g: Dictionary) -> float:
	var hp_pct := float(inp.hpPct)
	var hp: float = (
		float(g.CAP_HP_HI)
		if hp_pct > 0.5
		else float(g.CAP_HP_MID) if hp_pct > 0.2 else float(g.CAP_HP_LO)
	)
	var st: float = (
		float(g.CAP_ST_CTRL)
		if bool(inp.hasControl)
		else float(g.CAP_ST_DEBUFF) if bool(inp.hasCaptureDebuff) else 1.0
	)
	var pen := 1.0
	if float(inp.lvlDiff) > 0:
		pen = 1.0 - float(g.CAP_LVL_PEN) * minf(float(inp.lvlDiff), float(g.CAP_LVL_CAP))
	return minf(
		1.0,
		(
			float(inp.gourdBase)
			* float(inp.qualityCoef)
			* hp
			* st
			* maxf(0.0, pen)
			* (1.0 + float(inp.capBonus))
		)
	)


## JS number→string 口径（整数值不带小数点；对拍日志用）
static func fmt_num(v: float) -> String:
	if v == floorf(v):
		return str(int(v))
	return str(v)


# ---------- 战斗 ----------


func _make_unit(p: Dictionary, side: int) -> Dictionary:
	var uid := _uid_seq
	_uid_seq += 1
	var pet: Dictionary = cfg.pets[int(p.petId)]
	var skills: Array = []
	for id in p.skillIds:
		var skill: Dictionary = cfg.skills.get(int(id), {})
		if not skill.is_empty() and int(skill.learnLv) <= int(p.level):
			skills.append(skill)
	var stats: Dictionary = (
		BattleStats
		. compute_stats(
			int(pet.template),
			{
				"hp": pet.offHp,
				"atk": pet.offAtk,
				"def": pet.offDef,
				"spd": pet.offSpd,
				"mag": pet.offMag,
				"res": pet.offRes,
			},
			int(p.level),
			p.apts,
			int(p.realmBreaks),
			g
		)
	)
	var cds: Array = []
	cds.resize(skills.size())
	cds.fill(0)
	return {
		"uid": uid,
		"side": side,
		"petId": int(p.petId),
		"name": String(pet.name),
		"element": int(pet.element),
		"level": int(p.level),
		"stats": stats,
		"hp": int(stats.hp),
		"shield": 0,
		"rage": 0.0,
		"skills": skills,
		"cds": cds,
		"buffs": [],
		"alive": true,
		"captureable": bool(p.get("captureable", false)),
		"strategy": String(p.get("strategy", "random")),
		"ctrlHistory": [],
		"tauntTarget": -1,
		"tauntRemain": 0,
		"capBonus": 0.0,
	}


func _mod_total(u: Dictionary, k: String) -> float:
	var total: float = 0.0
	for b in u.buffs:
		if b.def.modStat == k:
			total += float(b.def.modPct) * float(b.stacks)
		if b.def.modStat2 == k:
			total += float(b.def.modPct2) * float(b.stacks)
	return total


func eff(u: Dictionary) -> Dictionary:
	var s: Dictionary = u.stats
	return {
		"hp": s.hp,
		"atk": float(s.atk) * (1.0 + _mod_total(u, "atk")),
		"def": float(s.def) * (1.0 + _mod_total(u, "def")),
		"spd": float(s.spd) * (1.0 + _mod_total(u, "spd")),
		"mag": float(s.mag) * (1.0 + _mod_total(u, "mag")),
		"res": float(s.res) * (1.0 + _mod_total(u, "res")),
		"dmg": 1.0 + _mod_total(u, "dmg"),
	}


func _has_control(u: Dictionary) -> bool:
	for b in u.buffs:
		if int(b.def.kind) == 2:
			return true
	return false


func _control_of(u: Dictionary, type: int) -> bool:
	for b in u.buffs:
		if int(b.def.control) == type:
			return true
	return false


func _enemies_of(u: Dictionary) -> Array:
	var res: Array = []
	for x in units:
		if int(x.side) != int(u.side) and bool(x.alive):
			res.append(x)
	return res


func _allies_of(u: Dictionary) -> Array:
	var res: Array = []
	for x in units:
		if int(x.side) == int(u.side) and bool(x.alive):
			res.append(x)
	return res


func _alive_count(side: int) -> int:
	var n := 0
	for x in units:
		if int(x.side) == side and bool(x.alive):
			n += 1
	return n


func run() -> Dictionary:
	## 重入守卫：outcome 已定时直接返回既有结果（防日志/事件二次污染）
	if outcome != "":
		return {
			"outcome": outcome,
			"rounds": round_num,
			"log": log_lines,
			"events": events,
			"capturedPetId": captured_pet_id,
		}
	var start_units: Array = []
	for u in units:
		start_units.append(
			{
				"u": int(u.uid),
				"s": int(u.side),
				"n": String(u.name),
				"hp": int(u.stats.hp),
				"el": int(u.element)
			}
		)
	_ev({"t": "start", "units": start_units})
	round_num = 1
	while round_num <= int(g.ROUND_CAP):
		_ev({"t": "round", "r": round_num})
		var order: Array = []
		for u in units:
			if bool(u.alive):
				order.append({"u": u, "r": rng.next()})
		order.sort_custom(_order_cmp)
		for e in order:
			var u: Dictionary = e.u
			if not bool(u.alive) or outcome != "":
				break
			_take_turn(u)
			if int(u.side) == 1 and _pending_capture_actor_uid > 0 and outcome == "":
				_settle_pending_capture()
		_round_end()
		if outcome != "":
			break
		if _alive_count(1) == 0:
			outcome = "victory"
		elif _alive_count(0) == 0:
			outcome = "defeat"
		round_num += 1
	if outcome == "":
		outcome = "timeout"
	log_lines.append("== 战斗结束：" + _outcome_text())
	_ev({"t": "end", "o": outcome, "r": round_num})
	return {
		"outcome": outcome,
		"rounds": round_num,
		"log": log_lines,
		"events": events,
		"capturedPetId": captured_pet_id,
	}


## 结构化事件（docs/10 §8.1）：只记录已发生事实，不消耗 RNG；与日志同点发射
func _ev(e: Dictionary) -> void:
	events.append(e)


func _order_cmp(a: Dictionary, b: Dictionary) -> bool:
	var sa := float(eff(a.u).spd)
	var sb := float(eff(b.u).spd)
	if sa != sb:
		return sa > sb
	return float(a.r) < float(b.r)


func _outcome_text() -> String:
	match outcome:
		"victory":
			return "胜利"
		"defeat":
			return "失败"
		"captured":
			return "捕捉成功（%d号灵宠入队）" % captured_pet_id
		_:
			return "超时判负"


## 日志显示名：敌方加前缀，便于同名灵宠区分
func _n(u: Dictionary) -> String:
	if int(u.side) == 1:
		return "[敌]" + String(u.name)
	return String(u.name)


func _take_turn(u: Dictionary) -> void:
	if _control_of(u, 1) or _control_of(u, 2) or _control_of(u, 3):
		log_lines.append("R%d %s 被控制无法行动" % [round_num, _n(u)])
		return
	if _control_of(u, 4) and rng.next() < 0.5:
		log_lines.append("R%d %s 麻痹无法行动" % [round_num, _n(u)])
		return
	if int(u.side) == 0 and _should_prepare_capture():
		_pending_capture_actor_uid = int(u.uid)
		log_lines.append("R%d %s 准备收妖" % [round_num, _n(u)])
		return
	var act := _choose_action(u)
	if act.is_empty():
		return
	var skill: Dictionary = act.skill
	var targets: Array = act.targets
	u.cds[u.skills.find(skill)] = skill.cd
	log_lines.append("R%d %s 施放【%s】" % [round_num, _n(u), String(skill.name)])
	var target_uids: Array = []
	for t0 in targets:
		target_uids.append(int(t0.uid))
	_ev({"t": "cast", "r": round_num, "u": int(u.uid), "s": String(skill.name), "tg": target_uids})
	for e in skill.effects:
		_apply_effect(u, skill, e, targets)
	if float(skill.rageGain) > 0:
		u.rage = minf(float(g.RAGE_MAX), float(u.rage) + float(skill.rageGain))


## Phase 0 自动捕捉策略：目标进入 20% 以下血线后，首个可行动我方单位准备收妖。
func _should_prepare_capture() -> bool:
	if not capture_mode or _pending_capture_actor_uid > 0:
		return false
	for x in units:
		if int(x.uid) == capture_target_uid and bool(x.alive):
			return float(x.hp) / float(x.stats.hp) < 0.2
	return false


func _settle_pending_capture() -> void:
	var actor_uid := _pending_capture_actor_uid
	_pending_capture_actor_uid = -1
	var target: Dictionary = {}
	for x in units:
		if int(x.uid) == capture_target_uid and bool(x.alive):
			target = x
			break
	if target.is_empty():
		return
	var quality_key := "CAP_Q%d" % int(cfg.pets[int(target.petId)].quality)
	try_capture(actor_uid, float(g.CAP_GOURD_JADE), float(g[quality_key]))


# ---------- AI 决策（03 §7） ----------


func _skill_ready(u: Dictionary, s: Dictionary) -> bool:
	if s.is_empty():
		return false
	return int(u.cds[u.skills.find(s)]) <= 0


func _choose_action(u: Dictionary) -> Dictionary:
	var sealed := _control_of(u, 5)
	var ult: Dictionary = u.skills[3] if u.skills.size() > 3 else {}
	var basic: Dictionary = u.skills[0]
	var actives: Array = []
	for i in range(1, mini(3, u.skills.size())):
		actives.append(u.skills[i])
	while actives.size() < 2:
		actives.append({})
	var enemy_targets := _pick_targets(u)

	if (
		not sealed
		and not ult.is_empty()
		and float(u.rage) >= float(g.RAGE_MAX)
		and _skill_ready(u, ult)
	):
		u.rage = 0.0
		return {"skill": ult, "targets": _select_targets(u, ult, enemy_targets)}
	if int(u.side) == 0:
		for s in actives:
			if _skill_ready(u, s) and _has_effect_type(s, "Heal"):
				var low: Array = []
				for a in _allies_of(u):
					if float(a.hp) / float(a.stats.hp) < 0.35:
						low.append(a)
				if not low.is_empty():
					return {"skill": s, "targets": _select_targets(u, s, low)}
		if capture_mode and capture_target_uid > 0:
			var t: Dictionary = {}
			for x in units:
				if int(x.uid) == capture_target_uid and bool(x.alive):
					t = x
					break
			if not t.is_empty() and not _has_control(t):
				for s in actives:
					if _skill_ready(u, s) and _has_control_buff_effect(s):
						return {"skill": s, "targets": [t]}
	if enemy_targets.is_empty():
		return {}
	var best: Dictionary = {}
	var best_score := -1.0
	for s in actives:
		if not _skill_ready(u, s):
			continue
		var dmg_e := _first_damage_effect(s)
		if dmg_e.is_empty():
			continue
		for t in enemy_targets:
			var te := eff(t)
			var ue := eff(u)
			var atk_or_mag := float(ue.atk) if float(ue.atk) > float(ue.mag) else float(ue.mag)
			var score: float = (
				atk_or_mag
				* float(dmg_e.power)
				* clash(int(u.element), int(t.element), g)
				* (1.0 + float(dmg_e.hitCount) - 1.0)
				* (1.0 if int(t.hp) < 999999 else 1.0)
			)
			var kill_w: float = 2.0 if float(dmg_e.power) * atk_or_mag >= float(t.hp) else 1.0
			var v := score * kill_w
			if v > best_score:
				best_score = v
				var sel := String(s.selector)
				var tg: Array = enemy_targets if sel == "enemy_all" or sel == "ally_all" else [t]
				best = {"skill": s, "targets": tg}
	if not best.is_empty() and rng.next() > 0.2:
		return best
	return {"skill": basic, "targets": [_pick_by_strategy(u, enemy_targets)]}


func _has_effect_type(s: Dictionary, type_name: String) -> bool:
	for e in s.effects:
		if e.type == type_name:
			return true
	return false


func _has_control_buff_effect(s: Dictionary) -> bool:
	for e in s.effects:
		if e.type == "ApplyBuff" and int(cfg.buffs[int(e.buffId)].kind) == 2:
			return true
	return false


func _first_damage_effect(s: Dictionary) -> Dictionary:
	for e in s.effects:
		if e.type == "PhysDamage" or e.type == "MagDamage":
			return e
	return {}


func _pick_by_strategy(u: Dictionary, es: Array) -> Dictionary:
	match String(u.strategy):
		"focus_weak":
			var best: Dictionary = es[0]
			for x in es:
				if not (float(best.hp) / float(best.stats.hp) <= float(x.hp) / float(x.stats.hp)):
					best = x
			return best
		"focus_squishy":
			var best: Dictionary = es[0]
			for x in es:
				if not (float(eff(best).def) <= float(eff(x).def)):
					best = x
			return best
		"caster_first":
			var best: Dictionary = es[0]
			for x in es:
				if not (float(eff(best).mag) >= float(eff(x).mag)):
					best = x
			return best
		_:
			var idx := floori(rng.next() * float(es.size()))
			if idx >= es.size():
				idx = es.size() - 1
			return es[idx]


func _pick_targets(u: Dictionary) -> Array:
	if int(u.tauntTarget) > 0:
		for x in units:
			if int(x.uid) == int(u.tauntTarget) and bool(x.alive):
				return [x]
	return _enemies_of(u)


func _select_targets(u: Dictionary, s: Dictionary, enemy_pool: Array) -> Array:
	var selector := String(s.selector)
	var allies := _allies_of(u)
	var result: Array = []
	match selector:
		"self":
			result = [u]
		"ally_all":
			result = allies
		"ally_lowest":
			result = [_min_hp_ratio(allies)]
		"enemy_all":
			result = enemy_pool
		"enemy_lowest":
			if not enemy_pool.is_empty():
				result = [_min_hp_ratio(enemy_pool)]
		"enemy_random":
			if not enemy_pool.is_empty():
				var idx := floori(rng.next() * float(enemy_pool.size()))
				if idx >= enemy_pool.size():
					idx = enemy_pool.size() - 1
				result = [enemy_pool[idx]]
		_:
			if not enemy_pool.is_empty():
				result = [enemy_pool[0]]
	return result


## TS reduce 口径：ratio <= 保留前者（先出现者优先）
func _min_hp_ratio(pool: Array) -> Dictionary:
	var best: Dictionary = pool[0]
	for x in pool:
		if not (float(best.hp) / float(best.stats.hp) <= float(x.hp) / float(x.stats.hp)):
			best = x
	return best


func _apply_effect(u: Dictionary, skill: Dictionary, e: Dictionary, targets: Array) -> void:
	var ue := eff(u)
	var self_applied := false
	for t0 in targets:
		if t0 == null:
			continue
		if bool(e.onSelf):
			if self_applied:
				continue
			self_applied = true
		var t: Dictionary = u if bool(e.onSelf) else t0
		var et := String(e.type)
		if et == "PhysDamage" or et == "MagDamage":
			var hit_target: Dictionary = t
			for _h in range(int(e.hitCount)):
				if not bool(hit_target.alive):
					var remaining := _enemies_of(u)
					if remaining.is_empty():
						break
					hit_target = _min_hp_ratio(remaining)
				var roll := {
					"hit": rng.next() < float(g.HIT_BASE),
					"crit": rng.next() < float(g.CRIT_BASE),
					"float":
					float(g.FLOAT_MIN) + rng.next() * (float(g.FLOAT_MAX) - float(g.FLOAT_MIN)),
				}
				var te := eff(hit_target)
				var mark := _find_mark_buff(hit_target, int(skill.element))
				var dmg := calc_damage(
					{
						"atkStat": ue.atk if et == "PhysDamage" else ue.mag,
						"power": e.power,
						"isPhys": et == "PhysDamage",
						"attackerElement": u.element,
						"defenderElement": hit_target.element,
						"skillElement": skill.element,
						"defStat": te.def if et == "PhysDamage" else te.res,
						"defenderLevel": hit_target.level,
						"dmgMod": ue.dmg,
						"markPct":
						(
							float(mark.def.markPct) * float(mark.stacks)
							if not mark.is_empty()
							else 0.0
						),
					},
					roll,
					g
				)
				if not bool(roll.hit):
					log_lines.append("  → %s 闪避" % _n(hit_target))
					_ev({"t": "dodge", "u": int(hit_target.uid)})
					continue
				_deal_damage(u, hit_target, dmg, int(skill.element), bool(roll.crit))
			_remove_first_dmg_buff(u)
		elif et == "Heal":
			var amount: int = roundi(float(ue.mag) * float(e.power))
			t.hp = mini(int(t.stats.hp), int(t.hp) + amount)
			log_lines.append("  → %s 回复 %d 点气血" % [_n(t), amount])
			_ev({"t": "heal", "u": int(t.uid), "a": amount, "hp": int(t.hp)})
		elif et == "Shield":
			var base := maxf(float(ue.mag), float(ue.def))
			var add: int = roundi(base * float(e.power))
			t.shield = int(t.shield) + add
			log_lines.append("  → %s 获得护盾 %d" % [_n(t), add])
			_ev({"t": "shield", "u": int(t.uid), "a": add})
		elif et == "ApplyBuff":
			var def: Dictionary = cfg.buffs.get(int(e.buffId))
			if def == null or def.is_empty():
				continue
			var chance: float = float(e.chance)
			if int(def.kind) == 2:
				var n_ctrl := 0
				if u != t:
					for r in t.ctrlHistory:
						if round_num - int(r) <= int(g.CTRL_DIM_WINDOW):
							n_ctrl += 1
				chance *= pow(float(g.CTRL_DIM), float(mini(n_ctrl, 3)))
				var ctrl_res: float = 0.0
				for b in t.buffs:
					ctrl_res += float(b.def.ctrlRes)
				chance *= 1.0 - ctrl_res
			if rng.next() >= chance:
				log_lines.append("  → %s 抵抗了【%s】" % [_n(t), String(def.name)])
				continue
			var ex := _find_buff_by_id(t, int(def.buffId))
			if not ex.is_empty():
				ex.stacks = mini(int(def.stacks), int(ex.stacks) + 1)
				ex.remain = int(def.duration)
			else:
				t.buffs.append({"def": def, "stacks": 1, "remain": int(def.duration)})
			if int(def.kind) == 2:
				t.ctrlHistory.append(round_num)
			log_lines.append("  → %s 获得【%s】" % [_n(t), String(def.name)])
			var buff_stacks := 1
			if not ex.is_empty():
				buff_stacks = int(ex.stacks)
			_ev({"t": "buff", "u": int(t.uid), "b": String(def.name), "st": buff_stacks})
		elif et == "Taunt":
			var duration := maxi(1, int(e.duration) if int(e.duration) > 0 else int(e.power))
			var affected: Array = _enemies_of(u) if bool(e.onSelf) else [t]
			for enemy in affected:
				enemy.tauntTarget = int(u.uid)
				enemy.tauntRemain = maxi(int(enemy.tauntRemain), duration)
			log_lines.append("  → %s 发起嘲讽" % _n(u))
		elif et == "RageModify":
			t.rage = maxf(0.0, minf(float(g.RAGE_MAX), float(t.rage) + float(e.power)))
			var sign := "+" if float(e.power) > 0 else ""
			log_lines.append("  → %s 怒气 %s%s" % [_n(t), sign, fmt_num(float(e.power))])
		elif et == "CaptureBonus":
			t.capBonus = float(t.capBonus) + float(e.power)
			log_lines.append("  → %s 捕捉准备就绪" % _n(t))
		elif et == "Detonate":
			var burn := _find_buff_by_id(t, 2)
			if not burn.is_empty():
				var dmg2: int = roundi(float(eff(u).mag) * float(e.power) * float(burn.stacks))
				_deal_damage(u, t, dmg2, 4)
				t.buffs.erase(burn)
				log_lines.append("  → 引爆 %s 的灼烧" % String(t.name))


func _find_mark_buff(t: Dictionary, element: int) -> Dictionary:
	for b in t.buffs:
		if int(b.def.kind) == 4 and int(b.def.markElement) == element:
			return b
	return {}


func _find_buff_by_id(t: Dictionary, buff_id: int) -> Dictionary:
	for b in t.buffs:
		if int(b.def.buffId) == buff_id:
			return b
	return {}


func _remove_first_dmg_buff(u: Dictionary) -> void:
	for b in u.buffs:
		if b.def.modStat == "dmg":
			u.buffs.erase(b)
			return


func _deal_damage(
	_attacker: Dictionary, t: Dictionary, dmg: int, skill_element: int, crit: bool = false
) -> void:
	if int(t.shield) > 0:
		var absorbed := mini(int(t.shield), dmg)
		t.shield = int(t.shield) - absorbed
		dmg -= absorbed
	if dmg > 0:
		t.hp = int(t.hp) - dmg
		t.rage = minf(float(g.RAGE_MAX), float(t.rage) + float(g.RAGE_HIT))
		var sleep := _find_control_buff(t, 3)
		if not sleep.is_empty():
			t.buffs.erase(sleep)
		if skill_element == 4:
			var frz := _find_control_buff(t, 1)
			if not frz.is_empty():
				t.buffs.erase(frz)
				var burn: Dictionary = cfg.buffs[2]
				t.buffs.append({"def": burn, "stacks": 1, "remain": int(burn.duration)})
		log_lines.append("  → %s 受到 %d 点伤害（剩 %d）" % [_n(t), dmg, maxi(0, int(t.hp))])
		_ev(
			{"t": "hit", "u": int(t.uid), "d": dmg, "hp": maxi(0, int(t.hp)), "c": 1 if crit else 0}
		)
		if int(t.hp) <= 0:
			_kill(t)
	else:
		log_lines.append("  → %s 的护盾吸收了全部伤害" % _n(t))
		_ev({"t": "hit", "u": int(t.uid), "d": 0, "hp": maxi(0, int(t.hp)), "c": 0})


func _find_control_buff(t: Dictionary, control_type: int) -> Dictionary:
	for b in t.buffs:
		if int(b.def.control) == control_type:
			return b
	return {}


func _kill(t: Dictionary) -> void:
	t.alive = false
	t.hp = 0
	log_lines.append("  ✕ %s 倒下" % _n(t))
	_ev({"t": "death", "u": int(t.uid)})
	var side_bench: Array = bench[int(t.side)]
	if not side_bench.is_empty():
		var sub: Dictionary = side_bench.pop_front()
		sub.rage = 50.0
		units.append(sub)
		log_lines.append("  ▲ 替补 %s 入场（怒气50）" % String(sub.name))
		_ev({"t": "sub", "u": int(sub.uid), "n": String(sub.name), "s": int(sub.side)})
	else:
		units.erase(t)


func _round_end() -> void:
	var alive_units: Array = []
	for x in units:
		if bool(x.alive):
			alive_units.append(x)
	for u in alive_units:
		var snapshot: Array = u.buffs.duplicate()
		for b in snapshot:
			if int(b.def.kind) == 1:
				var dmg: int = roundi(float(u.stats.hp) * float(b.def.dotPct) * float(b.stacks))
				u.hp = int(u.hp) - dmg
				log_lines.append(
					"R%d %s 因【%s】损失 %d 点气血" % [round_num, _n(u), String(b.def.name), dmg]
				)
				if int(u.hp) <= 0:
					_kill(u)
			elif int(b.def.kind) == 5 and float(b.def.dotPct) > 0:
				var heal: int = roundi(float(u.stats.hp) * float(b.def.dotPct) * float(b.stacks))
				u.hp = mini(int(u.stats.hp), int(u.hp) + heal)
			b.remain = int(b.remain) - 1
		var remain_buffs: Array = []
		for b in u.buffs:
			if int(b.remain) > 0:
				remain_buffs.append(b)
		u.buffs = remain_buffs
		var new_cds: Array = []
		for c in u.cds:
			new_cds.append(maxi(0, int(c) - 1))
		u.cds = new_cds
		u.capBonus = 0.0
		if int(u.tauntRemain) > 0:
			u.tauntRemain = int(u.tauntRemain) - 1
		if int(u.tauntRemain) <= 0:
			u.tauntTarget = -1


## 玩家捕捉指令（03 §10）：消耗行动回合，在敌方行动后结算
func try_capture(actor_uid: int, gourd_base: float, quality_coef: float) -> bool:
	var actor: Dictionary = {}
	for x in units:
		if int(x.uid) == actor_uid and bool(x.alive):
			actor = x
			break
	var t: Dictionary = {}
	for x in units:
		if int(x.uid) == capture_target_uid and bool(x.alive):
			t = x
			break
	if actor.is_empty() or t.is_empty() or not bool(t.captureable):
		return false
	var capture_debuff := false
	for b in t.buffs:
		if bool(b.def.captureLinked) and int(b.def.kind) != 2:
			capture_debuff = true
			break
	var rate := compute_capture_rate(
		{
			"gourdBase": gourd_base,
			"qualityCoef": quality_coef,
			"hpPct": float(t.hp) / float(t.stats.hp),
			"hasControl": _has_control(t),
			"hasCaptureDebuff": capture_debuff,
			"lvlDiff": int(t.level) - int(actor.level),
			"capBonus": actor.capBonus,
		},
		g
	)
	var ok := rng.next() < rate
	log_lines.append(
		(
			"R%d %s 祭出祖灵葫芦（成功率 %d%%）→ %s"
			% [round_num, _n(actor), floori(rate * 100.0 + 0.5), "收服！" if ok else "挣脱了"]
		)
	)
	_ev(
		{
			"t": "cap",
			"u": int(actor.uid),
			"tu": int(t.uid),
			"rt": floori(rate * 100.0 + 0.5),
			"ok": 1 if ok else 0
		}
	)
	if ok:
		captured_pet_id = int(t.petId)
		outcome = "captured"
	return ok
