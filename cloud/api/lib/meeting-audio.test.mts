import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';

import {
  deleteMeetingAudioFile,
  getMeetingAudioStorageConfig,
  hasMeetingAudioFile,
  saveMeetingAudioFile,
  saveMeetingAudioStream,
} from './meeting-audio.ts';

test('saveMeetingAudioFile stores meeting audio under configured storage root', async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'coco-interview-meeting-audio-'));
  const originalRoot = process.env.MEETING_AUDIO_STORAGE_ROOT;

  process.env.MEETING_AUDIO_STORAGE_ROOT = tempRoot;

  try {
    const filePath = await saveMeetingAudioFile('meeting-1', Buffer.from('hello audio'));

    assert.equal(filePath, path.join(tempRoot, 'meeting-1', 'audio.bin'));
    assert.equal(await hasMeetingAudioFile('meeting-1'), true);
    assert.equal((await readFile(filePath, 'utf8')).toString(), 'hello audio');

    await deleteMeetingAudioFile('meeting-1');
    assert.equal(await hasMeetingAudioFile('meeting-1'), false);
  } finally {
    if (originalRoot === undefined) {
      delete process.env.MEETING_AUDIO_STORAGE_ROOT;
    } else {
      process.env.MEETING_AUDIO_STORAGE_ROOT = originalRoot;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});

test('getMeetingAudioStorageConfig marks production fallback storage as not ready for persistent audio', () => {
  const storage = getMeetingAudioStorageConfig({
    env: {},
    cwd: '/srv/coco-interview',
    nodeEnv: 'production',
  });

  assert.equal(storage.rootPath, path.join('/srv/coco-interview', 'storage', 'meetings'));
  assert.equal(storage.configured, false);
  assert.equal(storage.persistent, false);
  assert.match(storage.message, /MEETING_AUDIO_STORAGE_ROOT/);
});

test('saveMeetingAudioStream writes audio payloads without buffering the whole file in the caller', async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'coco-interview-meeting-audio-stream-'));
  const originalRoot = process.env.MEETING_AUDIO_STORAGE_ROOT;

  process.env.MEETING_AUDIO_STORAGE_ROOT = tempRoot;

  try {
    const filePath = await saveMeetingAudioStream(
      'meeting-2',
      new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode('hello '));
          controller.enqueue(new TextEncoder().encode('stream'));
          controller.close();
        },
      })
    );

    assert.equal(filePath, path.join(tempRoot, 'meeting-2', 'audio.bin'));
    assert.equal(await hasMeetingAudioFile('meeting-2'), true);
    assert.equal((await readFile(filePath, 'utf8')).toString(), 'hello stream');
  } finally {
    if (originalRoot === undefined) {
      delete process.env.MEETING_AUDIO_STORAGE_ROOT;
    } else {
      process.env.MEETING_AUDIO_STORAGE_ROOT = originalRoot;
    }
    await rm(tempRoot, { recursive: true, force: true });
  }
});
