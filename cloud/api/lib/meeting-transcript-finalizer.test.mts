import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeDiarizedTranscript } from './meeting-transcript-finalizer.ts';

test('normalizeDiarizedTranscript maps provider speaker ids to stable keys', () => {
  const normalized = normalizeDiarizedTranscript({
    result: {
      utterances: [
        {
          text: '先介绍一下你最近做的项目。',
          start_time: 100,
          end_time: 1800,
          additions: { speaker: '2' },
        },
        {
          text: '我最近主要负责 iOS 客户端。',
          start_time: 2200,
          end_time: 4200,
          additions: { speaker: '8' },
        },
        {
          text: '那你做过哪些性能优化？',
          start_time: 4500,
          end_time: 5800,
          additions: { speaker: '2' },
        },
      ],
    },
  });

  assert.deepEqual(normalized.speakers, {
    spk_1: '说话人 1',
    spk_2: '说话人 2',
  });
  assert.deepEqual(
    normalized.segments.map((segment) => ({
      speaker: segment.speaker,
      text: segment.text,
      order: segment.order,
    })),
    [
      { speaker: 'spk_1', text: '先介绍一下你最近做的项目。', order: 0 },
      { speaker: 'spk_2', text: '我最近主要负责 iOS 客户端。', order: 1 },
      { speaker: 'spk_1', text: '那你做过哪些性能优化？', order: 2 },
    ]
  );
});
