import { isTrialExpired, type Account } from "../billing/trial.js";

type Response = { status: (code: number) => Response; send: (body?: string) => void };

// every request of a logged-in account goes through here: an expired trial gets the upgrade page
export function requireActiveAccount(account: Account, res: Response, next: () => void, now = new Date()) {
  if (isTrialExpired(account, now)) {
    res.status(402).send("Your trial has ended: upgrade to keep using the app.");
    return;
  }
  next();
}
