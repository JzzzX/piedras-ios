import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function read(relativePath) {
  return readFile(path.join(rootDir, relativePath), 'utf8');
}

test('key tracked files use coco-interview branding and remove legacy brand residues', async () => {
  const files = {
    readme: await read('README.md'),
    contributing: await read('CONTRIBUTING.md'),
    smokeTest: await read('scripts/asr_smoke_test.mjs'),
    apiPackage: await read('cloud/api/package.json'),
    proxyPackage: await read('cloud/asr-proxy/package.json'),
    apiLayout: await read('cloud/api/app/layout.tsx'),
    apiPage: await read('cloud/api/app/page.tsx'),
    adminConsole: await read('cloud/api/app/admin/AdminConsole.tsx'),
    workspaceDb: await read('cloud/api/lib/user-workspace-db.ts'),
    collectionDb: await read('cloud/api/lib/user-collection-db.ts'),
    startupState: await read('cloud/api/lib/startup-bootstrap-state.ts'),
    startupController: await read('cloud/api/lib/startup-bootstrap-controller.cjs'),
    finalizer: await read('cloud/api/lib/meeting-transcript-finalizer.ts'),
    apiServer: await read('cloud/api/server.cjs'),
    asrProxyServer: await read('cloud/asr-proxy/server.cjs'),
    apiEnvExample: await read('cloud/api/.env.example'),
  };

  assert.match(files.readme, /椰子面试 iOS/);
  assert.match(files.contributing, /CocoInterview/);
  assert.match(files.smokeTest, /COCO_INTERVIEW_BACKEND_URL/);
  assert.match(files.smokeTest, /COCO_INTERVIEW_BEARER_TOKEN/);
  assert.match(files.apiPackage, /"name": "coco-interview-cloud-api"/);
  assert.match(files.proxyPackage, /"name": "coco-interview-asr-proxy"/);
  assert.match(files.apiLayout, /椰子面试 Cloud/);
  assert.match(files.apiPage, /椰子面试 Cloud/);
  assert.match(files.adminConsole, /椰子面试 Cloud/);
  assert.match(files.workspaceDb, /椰子面试账号默认私有空间/);
  assert.match(files.collectionDb, /椰子面试默认笔记文件夹/);
  assert.match(files.collectionDb, /椰子面试最近删除文件夹/);
  assert.match(files.startupState, /__COCO_INTERVIEW_STARTUP_BOOTSTRAP_STATE__/);
  assert.match(files.startupController, /__COCO_INTERVIEW_STARTUP_BOOTSTRAP_STATE__/);
  assert.match(files.finalizer, /coco-interview-cloud-api/);
  assert.match(files.apiServer, /coco-interview-ios/);
  assert.match(files.apiServer, /coco-interview-proxy\/1\.0/);
  assert.match(files.asrProxyServer, /coco-interview-ios/);
  assert.match(files.asrProxyServer, /coco-interview-proxy\/1\.0/);
  assert.match(files.apiEnvExample, /cocointerview/);
  assert.match(files.apiEnvExample, /api\.coco-interview\.example\.com/);

  const legacyBrandPattern = new RegExp(
    [
      ['Pie', 'dras'].join(''),
      ['pie', 'dras'].join(''),
      ['PIE', 'DRAS'].join(''),
    ].join('|')
  );

  for (const [label, content] of Object.entries(files)) {
    assert.doesNotMatch(content, legacyBrandPattern, `${label} still contains legacy branding`);
  }
});
