import assert from 'node:assert/strict';
import { test } from 'node:test';
import { monthlyPrice, type Subscription } from './subscriptions.ts';

const subscription: Subscription = { accountId: 'acc_1', plan: 'pro', seats: 3 };

test('monthlyPrice multiplies the seat price of the plan', () => {
  assert.equal(monthlyPrice(subscription), 5700);
});
