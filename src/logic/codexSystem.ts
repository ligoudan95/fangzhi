/** 图鉴收集（TS 基准）——与 scripts/logic/codex_system.gd 镜像 */
export interface PetRef { petId: number }
export interface PetRow { petId: number; name: string; element: number; quality: number }

export function collectedIds(pets: PetRef[]): number[] {
  return [...new Set(pets.map(p => p.petId))];
}

export function completionRatio(pets: PetRef[], allPetIds: number[]): number {
  if (allPetIds.length === 0) return 0;
  return collectedIds(pets).length / allPetIds.length;
}

export function luckBonus(pets: PetRef[], allPetIds: number[]): number {
  return Math.floor(completionRatio(pets, allPetIds) / 0.05) * 10;
}

export function codexEntries(pets: PetRef[], petRows: PetRow[]): Array<{
  petId: number; name: string; element: number; quality: number; captured: boolean;
}> {
  const collected = new Set(pets.map(p => p.petId));
  return petRows.map(row => ({
    petId: row.petId, name: row.name, element: row.element, quality: row.quality,
    captured: collected.has(row.petId),
  }));
}
