import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ADMIN_SESSION_TTL_MS,
  createAdminSessionValue,
  verifyAdminSessionValue,
} from './admin-auth.ts';

const SECRET = 'admin-secret-for-tests';
const BASE_TIME = new Date('2026-03-26T10:00:00.000Z');

test('createAdminSessionValue issues a verifiable cookie payload', () => {
  const value = createAdminSessionValue(SECRET, {
    now: BASE_TIME,
  });

  const verified = verifyAdminSessionValue(SECRET, value, {
    now: new Date(BASE_TIME.getTime() + 60_000),
  });

  assert.equal(verified.valid, true);
  assert.equal(verified.expiresAt?.toISOString(), new Date(BASE_TIME.getTime() + ADMIN_SESSION_TTL_MS).toISOString());
});

test('verifyAdminSessionValue rejects tampered payloads', () => {
  const value = createAdminSessionValue(SECRET, {
    now: BASE_TIME,
  });

  const tampered = `${value.slice(0, -1)}x`;
  const verified = verifyAdminSessionValue(SECRET, tampered, {
    now: BASE_TIME,
  });

  assert.equal(verified.valid, false);
  assert.equal(verified.reason, 'signature_mismatch');
});

test('verifyAdminSessionValue rejects expired sessions', () => {
  const value = createAdminSessionValue(SECRET, {
    now: BASE_TIME,
  });

  const verified = verifyAdminSessionValue(SECRET, value, {
    now: new Date(BASE_TIME.getTime() + ADMIN_SESSION_TTL_MS + 1_000),
  });

  assert.equal(verified.valid, false);
  assert.equal(verified.reason, 'expired');
});
