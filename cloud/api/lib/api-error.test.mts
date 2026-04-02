import assert from 'node:assert/strict';
import test from 'node:test';

import apiErrorModule from './api-error.ts';

const { errorResponse } = apiErrorModule as typeof import('./api-error.ts');

test('errorResponse does not append undefined console arguments when cause is absent', async () => {
  const calls: unknown[][] = [];
  const originalConsoleError = console.error;
  console.error = ((...args: unknown[]) => {
    calls.push(args);
  }) as typeof console.error;

  try {
    const response = errorResponse(
      {
        route: '/api/meetings/[id]/audio',
        requestId: 'rid-audio-404',
      },
      404,
      '会议音频不存在'
    );

    assert.equal(response.status, 404);
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.length, 1);
    assert.match(String(calls[0]?.[0]), /route=\/api\/meetings\/\[id\]\/audio/);
    assert.doesNotMatch(String(calls[0]?.[0]), /undefined/);
  } finally {
    console.error = originalConsoleError;
  }
});
