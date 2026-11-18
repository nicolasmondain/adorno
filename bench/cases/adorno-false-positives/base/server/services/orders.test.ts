import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ObjectId } from 'mongodb';
import { withDb } from '../testing/db.ts';
import { listOrders } from './orders.ts';

const accountId = new ObjectId();

test('listOrders returns the orders of the account, newest first', async () => {
  await withDb(async (db) => {
    await db.collection('orders').insertMany([
      { accountId, customerId: new ObjectId(), total: 10, createdAt: new Date('2026-01-01') },
      { accountId, customerId: new ObjectId(), total: 30, createdAt: new Date('2026-02-01') },
      { accountId: new ObjectId(), customerId: new ObjectId(), total: 99, createdAt: new Date('2026-03-01') },
    ]);

    const orders = await listOrders(db, accountId);

    assert.deepEqual(orders.map((order) => order.total), [30, 10]);
  });
});
