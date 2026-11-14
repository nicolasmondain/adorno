import type { Db } from 'mongodb';

// Every index of the application, created at boot. `events` is the largest collection (hundreds of millions of
// documents, append-only): a query on it must be served by one of the indexes below.
export async function ensureIndexes(db: Db): Promise<void> {
  await db.collection('events').createIndex({ accountId: 1, createdAt: -1 });
  await db.collection('events').createIndex({ accountId: 1, contactId: 1, createdAt: -1 });
  await db.collection('contacts').createIndex({ accountId: 1, email: 1 }, { unique: true });
}
