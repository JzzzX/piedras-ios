import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

async function read(relativePath) {
  return readFile(new URL(relativePath, import.meta.url), 'utf8');
}

test('homepage is a clean status entry instead of embedding the admin console', async () => {
  const source = await read('./page.tsx');

  assert.doesNotMatch(source, /<AdminConsole\b/);
  assert.match(source, /进入后台/);
  assert.match(source, /\/healthz/);
});

test('/admin is a real page instead of redirecting back to the homepage anchor', async () => {
  const source = await read('./admin/page.tsx');

  assert.doesNotMatch(source, /\bredirect\(/);
  assert.match(source, /AdminConsole/);
});

test('admin console removes invite-code and legacy-workspace management UI', async () => {
  const source = await read('./admin/AdminConsole.tsx');

  assert.doesNotMatch(source, /邀请码/);
  assert.doesNotMatch(source, /legacy/);
  assert.doesNotMatch(source, /创建托管账号/);
  assert.doesNotMatch(source, /接管/);
  assert.match(source, /管理员登录/);
  assert.match(source, /重置/);
});

test('admin actions redirect back to /admin status messages', async () => {
  const source = await read('./admin/actions.ts');

  assert.doesNotMatch(source, /redirect\(`\/\?/);
  assert.doesNotMatch(source, /#account-admin/);
  assert.match(source, /redirect\(`\/admin\?/);
});
