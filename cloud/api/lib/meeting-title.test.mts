import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildHeuristicTitle,
  shouldRejectGeneratedTitle,
} from './meeting-title.ts';

test('shouldRejectGeneratedTitle rejects date-like testing sentence titles', () => {
  assert.equal(shouldRejectGeneratedTitle('2016年3月30日进行测试'), true);
  assert.equal(shouldRejectGeneratedTitle('今天是2016年3月30日'), true);
});

test('buildHeuristicTitle extracts a topic title instead of date and filler phrases', () => {
  const title = buildHeuristicTitle(
    '[麦克风]: 今天是 2016 年 3 月 30 日。\n[麦克风]: 现在进行语音测试。\n[麦克风]: 看一下这个转写的效果如何。',
    120,
    '2026-03-30T00:43:00+08:00'
  );

  assert.equal(title, '语音测试与转写效果验证');
});
