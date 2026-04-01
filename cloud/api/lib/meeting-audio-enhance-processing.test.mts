import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildMeetingAudioEnhanceStatus,
  createMeetingAudioEnhanceRuntimeState,
  enqueueMeetingAudioEnhance,
  markMeetingAudioEnhanceActive,
  markMeetingAudioEnhanceIdle,
  resolveMeetingAudioEnhanceInputStrategy,
} from './meeting-audio-enhance-processing.ts';

test('buildMeetingAudioEnhanceStatus normalizes persisted audio AI notes state for API payloads', () => {
  const status = buildMeetingAudioEnhanceStatus({
    audioEnhancedNotes: 'summary',
    audioEnhancedNotesStatus: 'processing',
    audioEnhancedNotesError: '',
    audioEnhancedNotesUpdatedAt: new Date('2026-03-31T08:00:00.000Z'),
    audioEnhancedNotesProvider: 'aihubmix',
    audioEnhancedNotesModel: 'gemini-3-flash-preview',
    audioEnhancedNotesAttempts: 2,
    audioEnhancedNotesRequestedAt: new Date('2026-03-31T07:59:59.000Z'),
    audioEnhancedNotesStartedAt: new Date('2026-03-31T08:00:01.000Z'),
  });

  assert.deepEqual(status, {
    audioEnhancedNotes: 'summary',
    audioEnhancedNotesStatus: 'processing',
    audioEnhancedNotesError: null,
    audioEnhancedNotesUpdatedAt: '2026-03-31T08:00:00.000Z',
    audioEnhancedNotesProvider: 'aihubmix',
    audioEnhancedNotesModel: 'gemini-3-flash-preview',
    audioEnhancedNotesAttempts: 2,
    audioEnhancedNotesRequestedAt: '2026-03-31T07:59:59.000Z',
    audioEnhancedNotesStartedAt: '2026-03-31T08:00:01.000Z',
  });
});

test('active meetings are not enqueued again for audio AI note generation', () => {
  const runtime = createMeetingAudioEnhanceRuntimeState();

  assert.equal(enqueueMeetingAudioEnhance(runtime, 'meeting-1'), true);
  assert.deepEqual(runtime.queue, ['meeting-1']);

  runtime.queue.shift();
  runtime.queued.delete('meeting-1');
  markMeetingAudioEnhanceActive(runtime, 'meeting-1');

  assert.equal(enqueueMeetingAudioEnhance(runtime, 'meeting-1'), false);
  assert.deepEqual(runtime.queue, []);
});

test('meeting can be enqueued again after audio AI note generation completes', () => {
  const runtime = createMeetingAudioEnhanceRuntimeState();

  markMeetingAudioEnhanceActive(runtime, 'meeting-1');
  markMeetingAudioEnhanceIdle(runtime, 'meeting-1');

  assert.equal(enqueueMeetingAudioEnhance(runtime, 'meeting-1'), true);
  assert.deepEqual(runtime.queue, ['meeting-1']);
});

test('audio AI notes keep inline mp3 strategy for AiHubMix requests', () => {
  const strategy = resolveMeetingAudioEnhanceInputStrategy({
    mimeType: 'audio/m4a',
    byteLength: 4 * 1024 * 1024,
  });

  assert.equal(strategy, 'inline_mp3');
});

test('audio AI notes keep inline mp3 strategy even for large inputs', () => {
  const strategy = resolveMeetingAudioEnhanceInputStrategy({
    mimeType: 'audio/m4a',
    byteLength: 24 * 1024 * 1024,
  });

  assert.equal(strategy, 'inline_mp3');
});
