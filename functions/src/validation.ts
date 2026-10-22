export function requireText(value: unknown, name: string): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 200 || value.includes('/')) {
    throw new Error(`${name} is invalid`);
  }
  return value.trim();
}
export function canBorrow(activeLoanId: unknown): boolean {
  return activeLoanId === null || activeLoanId === undefined;
}
export interface ItemFields {
  name: string;
  category: string;
  notes: string;
  locationId: string | null;
  photoPath: string | null;
}

export function itemFields(data: Record<string, unknown>, householdId: string, itemId: string): ItemFields {
  const name = requireText(data.name, 'name');
  const optionalText = (value: unknown, max: number, field: string): string => {
    if (value === undefined) return '';
    if (typeof value !== 'string' || value.trim().length > max) throw new Error(`${field} is invalid`);
    return value.trim();
  };
  const locationId = data.locationId == null ? null : requireText(data.locationId, 'locationId');
  const photoPath = data.photoPath == null ? null : data.photoPath;
  const prefix = `households/${householdId}/items/${itemId}/`;
  if (photoPath !== null && (typeof photoPath !== 'string' || !photoPath.startsWith(prefix)
    || !/^[A-Za-z0-9_-]+$/.test(photoPath.slice(prefix.length)))) throw new Error('photoPath is invalid');
  return { name, category: optionalText(data.category, 100, 'category'), notes: optionalText(data.notes, 2000, 'notes'), locationId, photoPath: photoPath as string | null };
}
