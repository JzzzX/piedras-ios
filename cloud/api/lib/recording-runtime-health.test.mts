import assert from 'node:assert/strict';
import test from 'node:test';

import { getMeetingAudioStorageConfig } from './meeting-audio.ts';
import { buildAudioFinalizationRuntimeStatus } from './recording-runtime-health.ts';

test('buildAudioFinalizationRuntimeStatus reports ffmpeg failures even when storage is configured', () => {
  const storage = getMeetingAudioStorageConfig({
    env: {
      MEETING_AUDIO_STORAGE_ROOT: '/data/meetings',
    },
    cwd: '/srv/piedras',
    nodeEnv: 'production',
  });

  const status = buildAudioFinalizationRuntimeStatus({
    storage,
    storageWriteOK: true,
    storageError: null,
    ffmpegAvailable: false,
    ffmpegMessage: 'ffmpeg missing',
    checkedAt: '2026-03-26T00:00:00.000Z',
  });

  assert.equal(status.configured, true);
  assert.equal(status.ready, false);
  assert.equal(status.ffmpegAvailable, false);
  assert.equal(status.storageReady, true);
  assert.match(status.message, /ffmpeg/);
});

test('buildAudioFinalizationRuntimeStatus becomes ready when storage and ffmpeg are available', () => {
  const storage = getMeetingAudioStorageConfig({
    env: {
      MEETING_AUDIO_STORAGE_ROOT: '/data/meetings',
    },
    cwd: '/srv/piedras',
    nodeEnv: 'production',
  });

  const status = buildAudioFinalizationRuntimeStatus({
    storage,
    storageWriteOK: true,
    storageError: null,
    ffmpegAvailable: true,
    ffmpegMessage: null,
    checkedAt: '2026-03-26T00:00:00.000Z',
  });

  assert.equal(status.configured, true);
  assert.equal(status.ready, true);
  assert.equal(status.ffmpegAvailable, true);
  assert.equal(status.storageReady, true);
  assert.match(status.message, /音频补转写就绪/);
});
