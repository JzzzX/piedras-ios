import assert from 'node:assert/strict';
import test from 'node:test';

import { buildMeetingAudioProcessingStatus } from './meeting-audio-processing.ts';

test('buildMeetingAudioProcessingStatus normalizes persisted audio processing state for API payloads', () => {
  const status = buildMeetingAudioProcessingStatus({
    audioProcessingState: 'processing',
    audioProcessingError: '',
    audioProcessingAttempts: 2,
    audioProcessingRequestedAt: new Date('2026-03-31T08:00:00.000Z'),
    audioProcessingStartedAt: new Date('2026-03-31T08:00:05.000Z'),
    audioProcessingCompletedAt: null,
  });

  assert.deepEqual(status, {
    audioProcessingState: 'processing',
    audioProcessingError: null,
    audioProcessingAttempts: 2,
    audioProcessingRequestedAt: '2026-03-31T08:00:00.000Z',
    audioProcessingStartedAt: '2026-03-31T08:00:05.000Z',
    audioProcessingCompletedAt: null,
  });
});

test('buildMeetingAudioProcessingStatus falls back to idle on unknown states', () => {
  const status = buildMeetingAudioProcessingStatus({
    audioProcessingState: 'mystery',
    audioProcessingError: 'boom',
    audioProcessingAttempts: 0,
    audioProcessingRequestedAt: null,
    audioProcessingStartedAt: null,
    audioProcessingCompletedAt: null,
  });

  assert.equal(status.audioProcessingState, 'idle');
  assert.equal(status.audioProcessingError, 'boom');
});
