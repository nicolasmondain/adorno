export const PLANS = ['free', 'pro', 'team'] as const;
export type Plan = (typeof PLANS)[number];

export interface Subscription {
  accountId: string;
  plan: Plan;
  seats: number;
}

const MONTHLY_CENTS_PER_SEAT: Record<Plan, number> = { free: 0, pro: 1900, team: 4900 };

export function monthlyPrice(subscription: Subscription): number {
  return MONTHLY_CENTS_PER_SEAT[subscription.plan] * subscription.seats;
}
