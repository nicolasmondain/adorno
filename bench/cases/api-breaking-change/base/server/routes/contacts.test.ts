import assert from 'node:assert/strict';
import { test } from 'node:test';
import express from 'express';
import request from 'supertest';
import type { Db } from 'mongodb';
import { withDb } from '../testing/db.ts';
import { contactsRouter, type Contact } from './contacts.ts';

function api(db: Db, accountId: string) {
  const app = express();
  app.use((_req, res, next) => {
    res.locals.accountId = accountId;
    next();
  });
  app.use(contactsRouter(db));
  return request(app);
}

test('GET /v1/contacts lists a page of the account and counts every contact', async () => {
  await withDb(async (db) => {
    await db.collection<Contact>('contacts').insertMany([
      { _id: 'con_1', accountId: 'acc_1', email: 'ada@example.test', createdAt: new Date('2026-01-01') },
      { _id: 'con_2', accountId: 'acc_1', email: 'bob@example.test', createdAt: new Date('2026-01-02') },
      { _id: 'con_3', accountId: 'acc_2', email: 'eve@example.test', createdAt: new Date('2026-01-03') },
    ]);

    const res = await api(db, 'acc_1').get('/v1/contacts?limit=1').expect(200);

    assert.deepEqual(res.body.items.map((contact: Contact) => contact._id), ['con_2']);
    assert.equal(res.body.total, 2);
  });
});
