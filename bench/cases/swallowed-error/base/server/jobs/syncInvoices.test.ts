import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { FetchInvoices } from '../services/billingProvider.ts';
import { withDb } from '../testing/db.ts';
import { syncInvoices } from './syncInvoices.ts';

interface BilledAccount {
  _id: string;
  billingId: string;
}

const accounts: BilledAccount[] = [
  { _id: 'acc_1', billingId: 'bill_1' },
  { _id: 'acc_2', billingId: 'bill_2' },
];

test('syncInvoices upserts the invoices of every billed account', async () => {
  await withDb(async (db) => {
    await db.collection<BilledAccount>('accounts').insertMany(accounts);
    const fetchInvoices: FetchInvoices = async (billingId) => [
      { id: `inv_${billingId}`, amountCents: 1200, issuedAt: '2026-01-01' },
    ];

    const report = await syncInvoices(db, fetchInvoices);

    assert.deepEqual(report, { accounts: 2, invoices: 2 });
    assert.equal(await db.collection('invoices').countDocuments(), 2);
  });
});
