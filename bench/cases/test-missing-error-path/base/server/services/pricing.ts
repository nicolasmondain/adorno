// Amounts are integers, in cents.
export function applyDiscount(totalCents: number, percent: number): number {
  if (percent < 0 || percent > 100) {
    throw new RangeError(`discount out of range: ${percent}`);
  }
  return Math.round((totalCents * (100 - percent)) / 100);
}
