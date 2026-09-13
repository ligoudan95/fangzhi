/** 灵宠派遣（TS 基准）——与 scripts/logic/pet_dispatch.gd 镜像。docs/05 §4 */
export interface PetCondition { staminaMilli: number; moodMilli: number; assignmentKind?: string; assignmentId?: number }
export interface G { STAMINA_MAX?: number; STAMINA_DRAIN_PER_H?: number; MOOD_MAX?: number; BARN_MOOD_REGEN_PER_H?: number }

export function canDispatch(condition: PetCondition, g: G): boolean {
  return (condition.staminaMilli ?? 100_000) >= 20_000;
}

export function dispatchEfficiency(condition: PetCondition, buildingBonus: number, g: G): number {
  const staminaMax = (g.STAMINA_MAX ?? 100) * 1000;
  const moodMax = (g.MOOD_MAX ?? 100) * 1000;
  const sr = Math.min(1, Math.max(0, condition.staminaMilli / staminaMax));
  const mr = Math.min(1, Math.max(0, condition.moodMilli / moodMax));
  return Math.min(2, Math.max(0.1, sr * 0.7 + mr * 0.3 + buildingBonus));
}

export function settleDispatch(condition: PetCondition, hours: number, g: G): PetCondition {
  const drainPerH = (g.STAMINA_DRAIN_PER_H ?? 10) * 1000;
  return {
    ...condition,
    staminaMilli: Math.max(0, condition.staminaMilli - Math.round(drainPerH * hours)),
    moodMilli: Math.max(0, condition.moodMilli - Math.round(5000 * hours)),
  };
}

export function settleRest(condition: PetCondition, hours: number, barnLevel: number, g: G): PetCondition {
  const staminaMax = (g.STAMINA_MAX ?? 100) * 1000;
  const moodMax = (g.MOOD_MAX ?? 100) * 1000;
  const staminaRegen = Math.round((15 + 1.5 * barnLevel) * 1000 * hours);
  const moodRegen = Math.round((g.BARN_MOOD_REGEN_PER_H ?? 20) * 1000 * hours);
  return {
    ...condition,
    staminaMilli: Math.min(staminaMax, condition.staminaMilli + staminaRegen),
    moodMilli: Math.min(moodMax, condition.moodMilli + moodRegen),
  };
}
