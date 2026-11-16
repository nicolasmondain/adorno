import assert from 'node:assert/strict';
import { test } from 'node:test';
import { invoiceLine } from './exports.ts';

test('invoiceLine gives the number and the total in euros', () => {
  assert.equal(invoiceLine({ number: 'F-1', totalCents: 12345 }), 'F-1;123.45');
});
