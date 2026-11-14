import assert from 'node:assert/strict';
import { test } from 'node:test';
import express, { type NextFunction, type Request, type Response } from 'express';
import request from 'supertest';
import type { Db } from 'mongodb';
import { ForbiddenError, type Member } from '../lib/permissions.ts';
import { withDb } from '../testing/db.ts';
import { invoicesRouter, type Invoice } from './invoices.ts';

const reader: Member = { id: 'mem_1', accountId: 'acc_1', permissions: ['invoices:read'] };
const writer: Member = { id: 'mem_2', accountId: 'acc_1', permissions: ['invoices:read', 'invoices:write'] };
const draft: Invoice = { _id: 'inv_1', accountId: 'acc_1', amount: 100, status: 'draft' };

function api(db: Db, member: Member) {
  const app = express().use(express.json());
  app.use((_req, res, next) => {
    res.locals.member = member;
    next();
  });
  app.use(invoicesRouter(db));
  app.use((error: unknown, _req: Request, res: Response, _next: NextFunction) => {
    res.status(error instanceof ForbiddenError ? error.status : 500).end();
  });
  return request(app);
}

test('GET /invoices/:id returns the invoice of the account', async () => {
  await withDb(async (db) => {
    await db.collection<Invoice>('invoices').insertOne(draft);
    const res = await api(db, reader).get('/invoices/inv_1').expect(200);
    assert.equal(res.body.amount, 100);
  });
});

test('PATCH /invoices/:id updates a draft', async () => {
  await withDb(async (db) => {
    await db.collection<Invoice>('invoices').insertOne(draft);
    await api(db, writer).patch('/invoices/inv_1').send({ amount: 250 }).expect(204);
    const invoice = await db.collection<Invoice>('invoices').findOne({ _id: 'inv_1' });
    assert.equal(invoice?.amount, 250);
  });
});

test('PATCH /invoices/:id is refused without invoices:write', async () => {
  await withDb(async (db) => {
    await db.collection<Invoice>('invoices').insertOne(draft);
    await api(db, reader).patch('/invoices/inv_1').send({ amount: 250 }).expect(403);
  });
});
