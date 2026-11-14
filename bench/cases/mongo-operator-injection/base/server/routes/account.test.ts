import assert from 'node:assert/strict';
import { test } from 'node:test';
import express from 'express';
import request from 'supertest';
import type { Db } from 'mongodb';
import { withDb } from '../testing/db.ts';
import { accountRouter } from './account.ts';

function api(db: Db) {
  return request(express().use(express.json()).use(accountRouter(db)));
}

test('GET /health answers ok', async () => {
  await withDb(async (db) => {
    const res = await api(db).get('/health').expect(200);
    assert.deepEqual(res.body, { ok: true });
  });
});
