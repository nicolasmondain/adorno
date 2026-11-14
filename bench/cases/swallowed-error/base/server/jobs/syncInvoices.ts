import type { Db } from 'mongodb';
import type { FetchInvoices } from '../services/billingProvider.ts';

interface BilledAccount {
  _id: string;
  billingId: string;
}

export interface SyncReport {
  accounts: number;
  invoices: number;
}

// Nightly job. The scheduler retries a run that throws and pages the on-call engineer after three failed runs.
export async function syncInvoices(db: Db, fetchInvoices: FetchInvoices): Promise<SyncReport> {
  const accounts = await db
    .collection<BilledAccount>('accounts')
    .find({ billingId: { $exists: true } }, { projection: { billingId: 1 } })
    .toArray();

  const report: SyncReport = { accounts: 0, invoices: 0 };
  for (const account of accounts) {
    const invoices = await fetchInvoices(account.billingId);
    if (invoices.length > 0) {
      await db.collection('invoices').bulkWrite(
        invoices.map((invoice) => ({
          updateOne: {
            filter: { _id: invoice.id },
            update: {
              $set: { accountId: account._id, amountCents: invoice.amountCents, issuedAt: new Date(invoice.issuedAt) },
            },
            upsert: true,
          },
        })),
      );
    }
    report.accounts += 1;
    report.invoices += invoices.length;
  }
  return report;
}
