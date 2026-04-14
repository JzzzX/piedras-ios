import assert from 'node:assert/strict';
import test from 'node:test';

import {
  generateInviteCode,
  hashPassword,
  hashSessionToken,
  isPasswordValid,
  normalizeEmail,
  normalizeInviteCode,
  verifyPassword,
  generateSessionToken,
} from './auth.ts';

test('normalizeEmail trims whitespace and lowercases the address', () => {
  assert.equal(normalizeEmail('  Test.User@Example.COM  '), 'test.user@example.com');
});

test('isPasswordValid requires at least eight characters', () => {
  assert.equal(isPasswordValid('1234567'), false);
  assert.equal(isPasswordValid('12345678'), true);
});

test('normalizeInviteCode strips spaces and hyphens before comparing', () => {
  assert.equal(normalizeInviteCode(' pie-12 ab '), 'PIE12AB');
});

test('hashPassword produces a verifiable hash for the original password', async () => {
  const passwordHash = await hashPassword('coco-interview-demo-123');

  assert.notEqual(passwordHash, 'coco-interview-demo-123');
  assert.equal(await verifyPassword('coco-interview-demo-123', passwordHash), true);
  assert.equal(await verifyPassword('coco-interview-demo-456', passwordHash), false);
});

test('generateSessionToken creates url-safe random tokens', () => {
  const first = generateSessionToken();
  const second = generateSessionToken();

  assert.notEqual(first, second);
  assert.match(first, /^[A-Za-z0-9_-]+$/);
  assert.ok(first.length >= 32);
});

test('hashSessionToken is deterministic for the same token', () => {
  const token = 'session-token-example';

  assert.equal(hashSessionToken(token), hashSessionToken(token));
  assert.notEqual(hashSessionToken(token), token);
});

test('generateInviteCode returns a readable grouped code', () => {
  const inviteCode = generateInviteCode();

  assert.match(inviteCode, /^[A-Z2-9]{5}-[A-Z2-9]{5}$/);
});
