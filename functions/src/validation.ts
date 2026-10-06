export function requireText(value: unknown, name: string): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 200 || value.includes('/')) {
    throw new Error(`${name} is invalid`);
  }
  return value.trim();
}
export function canBorrow(activeLoanId: unknown): boolean {
  return activeLoanId === null || activeLoanId === undefined;
}
