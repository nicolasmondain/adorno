import assert from 'node:assert/strict';
import { test } from 'node:test';
import { formatDuration } from './duration.ts';

test('formatDuration shows seconds under a minute', () => {
  assert.equal(formatDuration(0), '0s');
  assert.equal(formatDuration(45), '45s');
});

test('formatDuration shows minutes, with seconds when there are some', () => {
  assert.equal(formatDuration(60), '1m');
  assert.equal(formatDuration(125), '2m 5s');
});

test('formatDuration shows hours, with minutes when there are some', () => {
  assert.equal(formatDuration(3600), '1h');
  assert.equal(formatDuration(3725), '1h 2m');
});
