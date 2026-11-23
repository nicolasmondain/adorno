export const DAY_MS = 24 * 60 * 60 * 1000;

export type Account = { id: string; plan: "trial" | "paid"; trialEndsAt: Date };

// whole days left, as the banner shows them ("3 days left")
export function trialDaysLeft(account: Account, now: Date): number {
  return Math.floor((account.trialEndsAt.getTime() - now.getTime()) / DAY_MS);
}

export function isTrialExpired(account: Account, now: Date): boolean {
  return account.plan === "trial" && trialDaysLeft(account, now) <= 0;
}
