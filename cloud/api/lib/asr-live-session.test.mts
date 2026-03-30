import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildAsrSessionContext,
  buildRecognitionSnapshot,
} from './asr-live-session.ts';

test('buildRecognitionSnapshot preserves utterance order and definite flags', () => {
  const snapshot = buildRecognitionSnapshot(
    {
      result: {
        text: '产品评审 下一步确认排期',
        utterances: [
          {
            text: '产品评审',
            start_time: 0,
            end_time: 820,
            definite: true,
          },
          {
            text: '下一步确认排期',
            start_time: 900,
            end_time: 2100,
            definite: false,
          },
        ],
      },
    },
    {
      revision: 7,
      fallbackEndTimeMs: 2100,
    }
  );

  assert.deepEqual(snapshot, {
    revision: 7,
    fullText: '产品评审 下一步确认排期',
    audioEndTimeMs: 2100,
    utterances: [
      {
        text: '产品评审',
        startTimeMs: 0,
        endTimeMs: 820,
        definite: true,
      },
      {
        text: '下一步确认排期',
        startTimeMs: 900,
        endTimeMs: 2100,
        definite: false,
      },
    ],
  });
});

test('buildAsrSessionContext keeps the newest business context entries first', () => {
  const context = JSON.parse(
    buildAsrSessionContext({
      workspaceName: 'Piedras 产品组',
      meetingTitle: '周一产品评审',
      recentTranscriptTexts: [
        '旧记录 1',
        '旧记录 2',
        '刚确认的里程碑',
      ],
      noteSummary: '重点关注 ASR 动态纠错和版本排期',
      maxTranscriptEntries: 2,
    })
  );

  assert.deepEqual(context, {
    workspace_name: 'Piedras 产品组',
    meeting_title: '周一产品评审',
    note_summary: '重点关注 ASR 动态纠错和版本排期',
    recent_transcripts: [
      '刚确认的里程碑',
      '旧记录 2',
    ],
  });
});
