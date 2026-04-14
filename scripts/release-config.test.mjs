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
  const project = await read('CocoInterview.xcodeproj/project.pbxproj');

  const appBuildMatches = project.match(
    /CURRENT_PROJECT_VERSION = 22;[\s\S]*?MARKETING_VERSION = 1\.0;[\s\S]*?PRODUCT_BUNDLE_IDENTIFIER = io\.iftech\.cocointerview;/g
  );
  const widgetBuildMatches = project.match(
    /CURRENT_PROJECT_VERSION = 22;[\s\S]*?MARKETING_VERSION = 1\.0;[\s\S]*?PRODUCT_BUNDLE_IDENTIFIER = io\.iftech\.cocointerview\.recordingwidget;/g
  );

  assert.equal(appBuildMatches?.length ?? 0, 2);
  assert.equal(widgetBuildMatches?.length ?? 0, 2);
});

test('project uses CocoInterview naming, callback scheme, and backend config key', async () => {
  const project = await read('CocoInterview.xcodeproj/project.pbxproj');
  const mainScheme = await read('CocoInterview.xcodeproj/xcshareddata/xcschemes/CocoInterview.xcscheme');
  const appInfoPlist = await read('CocoInterview-Info.plist');

  assert.match(project, /INFOPLIST_KEY_COCO_INTERVIEW_BACKEND_BASE_URL/);
  assert.doesNotMatch(project, /PIEDRAS_BACKEND_BASE_URL/);
  assert.match(mainScheme, /BuildableName = "CocoInterview\.app"/);
  assert.match(mainScheme, /BlueprintName = "CocoInterview"/);
  assert.match(appInfoPlist, /io\.iftech\.cocointerview\.auth/);
  assert.match(appInfoPlist, /<string>cocointerview<\/string>/);
});

test('main app Info.plist declares non-exempt encryption for TestFlight visibility', async () => {
  const infoPlist = await read('CocoInterview-Info.plist');

  assert.match(infoPlist, /ITSAppUsesNonExemptEncryption/);
  assert.match(infoPlist, /<false\/>/);
});
