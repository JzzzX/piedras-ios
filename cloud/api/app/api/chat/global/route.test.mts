import assert from 'node:assert/strict';
import test from 'node:test';

import { selectRetrievalResult } from '../../../../lib/global-chat-selection.ts';

test('selectRetrievalResult prefers client-provided local retrieval context', () => {
  const result = selectRetrievalResult({
    localRetrievalContext: '[S1] 会议：灰度上线会\n- 评论里说明仅覆盖 iOS 内测用户',
    localRetrievalSources: [
      {
        ref: 'S1',
        type: 'meeting',
        title: '灰度上线会',
        date: '2026-03-23T10:00:00.000Z',
      },
    ],
    fallback: {
      context: '[S9] 会议：远端结果',
      sources: [
        {
          ref: 'S9',
          type: 'meeting',
          title: '远端结果',
          date: '2026-03-20T10:00:00.000Z',
          score: 0.5,
          snippets: ['旧内容'],
        },
      ],
    },
  });

  assert.equal(result.context, '[S1] 会议：灰度上线会\n- 评论里说明仅覆盖 iOS 内测用户');
  assert.deepEqual(result.sources, [
    {
      ref: 'S1',
      type: 'meeting',
      title: '灰度上线会',
      date: '2026-03-23T10:00:00.000Z',
    },
  ]);
});
