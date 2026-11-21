`workflow:issue:fix` on this Notion page (`agent:fix`):
- Make `isTrialExpired` compare `now.getTime() >= account.trialEndsAt.getTime()` (still for `plan === "trial"`), separate from the display value.
- Leave `trialDaysLeft` as it is for the banner.
- Add `server/billing/trial.test.ts`, covering the hours before and after `trialEndsAt` plus the middleware 402 path.

Separately, the owner should ask N0ALICE or Support what the banner should say during the last 24 h ("0 days left" or "Last day"). The owner may also want to check whether the affected accounts need their access restored or their trial extended. That is an ops/support action, not code.
