import assert from 'node:assert/strict';
import { test } from 'node:test';
import { applyDiscount } from './pricing.ts';

test('applyDiscount takes the percentage off', () => {
  assert.equal(applyDiscount(2000, 25), 1500);
});

test('applyDiscount rejects a percentage out of range', () => {
  assert.throws(() => applyDiscount(2000, 120), RangeError);
});
