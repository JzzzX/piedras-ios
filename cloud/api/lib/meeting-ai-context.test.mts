import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildGlobalChatContextMessage,
  buildMeetingMaterialContext,
} from './meeting-ai-context.ts';

test('buildMeetingMaterialContext appends segment comments after ai notes', () => {
  const content = buildMeetingMaterialContext({
    transcript: '[Speaker A]: 我们下周先灰度上线。',
    userNotes: '用户记录了灰度计划',
    enhancedNotes: 'AI 已总结主要行动项',
    segmentCommentsContext:
      '--- 转写片段评论 ---\n[00:12] 原句：我们下周先灰度上线。\n评论：这里的“下周”其实指 4 月第一周。',
  });

  assert.match(content, /--- 会议转写记录 ---/);
  assert.match(content, /--- 用户笔记要点 ---/);
  assert.match(content, /--- AI 会议纪要 ---/);
  assert.match(content, /--- 转写片段评论 ---/);
  assert.match(content, /评论：这里的“下周”其实指 4 月第一周。/);
});

test('buildGlobalChatContextMessage appends local comment context after retrieval context', () => {
  const content = buildGlobalChatContextMessage({
    retrievalContext: '[S1] 会议：灰度上线会\n- 下周先灰度上线',
    localCommentContext:
      '--- 本地补充评论上下文 ---\n会议：灰度上线会\n[00:12] 原句：我们下周先灰度上线。\n评论：这里的灰度范围只覆盖 iOS 内测用户。',
  });

  assert.match(content, /^\[S1] 会议：灰度上线会/m);
  assert.match(content, /--- 本地补充评论上下文 ---/);
  assert.match(content, /会议：灰度上线会/);
  assert.match(content, /评论：这里的灰度范围只覆盖 iOS 内测用户。/);
});
