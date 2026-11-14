import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ObjectId } from 'mongodb';
import { withDb } from '../testing/db.ts';
import { listContactEvents } from './events.ts';

const accountId = new ObjectId();
const contactId = new ObjectId();

test('listContactEvents returns the events of the contact, newest first', async () => {
  await withDb(async (db) => {
    await db.collection('events').insertMany([
      { accountId, contactId, campaignId: null, type: 'sent', createdAt: new Date('2026-01-01') },
      { accountId, contactId, campaignId: null, type: 'opened', createdAt: new Date('2026-01-02') },
      { accountId, contactId: new ObjectId(), campaignId: null, type: 'sent', createdAt: new Date('2026-01-03') },
    ]);

    const events = await listContactEvents(db, accountId, contactId);

    assert.deepEqual(events.map((event) => event.type), ['opened', 'sent']);
  });
});
