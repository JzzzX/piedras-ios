import crypto from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(crypto.scrypt);

const PASSWORD_SALT_BYTES = 16;
const PASSWORD_KEY_BYTES = 64;
const SESSION_TOKEN_BYTES = 32;
const MIN_PASSWORD_LENGTH = 8;
const INVITE_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const INVITE_CODE_LENGTH = 10;

function toBase64URL(value: Buffer | string) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function fromBase64URL(value: string) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padding = normalized.length % 4 === 0 ? '' : '='.repeat(4 - (normalized.length % 4));
  return Buffer.from(`${normalized}${padding}`, 'base64');
}

export function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

export function isPasswordValid(password: string) {
  return password.trim().length >= MIN_PASSWORD_LENGTH;
}

export function normalizeInviteCode(code: string) {
  return code.trim().replace(/[\s-]+/g, '').toUpperCase();
}

export async function hashPassword(password: string) {
  const salt = crypto.randomBytes(PASSWORD_SALT_BYTES);
  const derivedKey = (await scrypt(password, salt, PASSWORD_KEY_BYTES)) as Buffer;
  return `scrypt$${toBase64URL(salt)}$${toBase64URL(derivedKey)}`;
}

export async function verifyPassword(password: string, storedHash: string) {
  const [scheme, encodedSalt, encodedHash] = storedHash.split('$');
  if (scheme !== 'scrypt' || !encodedSalt || !encodedHash) {
    return false;
  }

  const salt = fromBase64URL(encodedSalt);
  const expectedHash = fromBase64URL(encodedHash);
  const candidateHash = (await scrypt(password, salt, expectedHash.length)) as Buffer;

  return crypto.timingSafeEqual(candidateHash, expectedHash);
}

export function generateSessionToken() {
  return toBase64URL(crypto.randomBytes(SESSION_TOKEN_BYTES));
}

export function hashSessionToken(token: string) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function generateInviteCode() {
  let result = '';
  const randomBytes = crypto.randomBytes(INVITE_CODE_LENGTH);

  for (let index = 0; index < INVITE_CODE_LENGTH; index += 1) {
    result += INVITE_CODE_ALPHABET[randomBytes[index] % INVITE_CODE_ALPHABET.length];
  }

  return `${result.slice(0, 5)}-${result.slice(5)}`;
}
