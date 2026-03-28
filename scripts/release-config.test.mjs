import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function read(relativePath) {
  return readFile(path.join(rootDir, relativePath), 'utf8');
}

test('app and widget build settings use the next TestFlight build number', async () => {
  const project = await read('Piedras.xcodeproj/project.pbxproj');

  const appBuildMatches = project.match(
    /CURRENT_PROJECT_VERSION = 22;[\s\S]*?MARKETING_VERSION = 1\.0;[\s\S]*?PRODUCT_BUNDLE_IDENTIFIER = com\.mediocre\.piedras;/g
  );
  const widgetBuildMatches = project.match(
    /CURRENT_PROJECT_VERSION = 22;[\s\S]*?MARKETING_VERSION = 1\.0;[\s\S]*?PRODUCT_BUNDLE_IDENTIFIER = com\.mediocre\.piedras\.recordingwidget;/g
  );

  assert.equal(appBuildMatches?.length ?? 0, 2);
  assert.equal(widgetBuildMatches?.length ?? 0, 2);
});

test('main app Info.plist declares non-exempt encryption for TestFlight visibility', async () => {
  const infoPlist = await read('Piedras-Info.plist');

  assert.match(infoPlist, /ITSAppUsesNonExemptEncryption/);
  assert.match(infoPlist, /<false\/>/);
});
