import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildAudioMeetingMaterialContext,
  buildGlobalChatContextMessage,
  buildMeetingMaterialContext,
} from './meeting-ai-context.ts';

test('buildMeetingMaterialContext appends segment comments after ai notes', () => {
  const content = buildMeetingMaterialContext({
    transcript: '[Speaker A]: 我们下周先灰度上线。',
    userNotes: '用户记录了灰度计划',
    enhancedNotes: 'AI 已总结主要行动项',
    noteAttachmentsContext:
      '--- 主笔记附件资料 ---\n图片1：\n白板写着：4 月 8 日灰度，4 月 15 日全量。',
    segmentCommentsContext:
      '--- 转写片段评论 ---\n[00:12] 原句：我们下周先灰度上线。\n评论：这里的“下周”其实指 4 月第一周。',
  });

  assert.match(content, /--- 会议转写记录 ---/);
  assert.match(content, /--- 用户笔记要点 ---/);
  assert.match(content, /--- AI 会议纪要 ---/);
  assert.match(content, /--- 主笔记附件资料 ---/);
  assert.match(content, /4 月 8 日灰度/);
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

test('buildMeetingMaterialContext truncates oversized sections when limits are provided', () => {
  const content = buildMeetingMaterialContext(
    {
      transcript: '转写'.repeat(20),
      userNotes: '笔记'.repeat(20),
      noteAttachmentsContext: '附件'.repeat(20),
      segmentCommentsContext: '评论'.repeat(20),
    },
    {
      transcriptMaxChars: 12,
      userNotesMaxChars: 12,
      noteAttachmentsMaxChars: 12,
      segmentCommentsMaxChars: 12,
    } as any
  );

  assert.match(content, /转写转写转写转写转写转写（以下内容已截断）/);
  assert.match(content, /笔记笔记笔记笔记笔记笔记（以下内容已截断）/);
  assert.match(content, /附件附件附件附件附件附件（以下内容已截断）/);
  assert.match(content, /评论评论评论评论评论评论（以下内容已截断）/);
});

test('buildAudioMeetingMaterialContext excludes transcript and keeps attachment/comment context', () => {
  const content = buildAudioMeetingMaterialContext({
    userNotes: '用户笔记里写了先灰度一周。',
    noteAttachmentsContext:
      '--- 主笔记附件资料 ---\n图片1：\n白板写着：4 月 8 日灰度，4 月 15 日全量。',
    segmentCommentsContext:
      '--- 转写片段评论 ---\n[00:12] 原句：我们下周先灰度上线。\n评论：这里的“下周”其实指 4 月第一周。',
  });

  assert.doesNotMatch(content, /--- 会议转写记录 ---/);
  assert.match(content, /--- 用户笔记要点 ---/);
  assert.match(content, /--- 主笔记附件资料 ---/);
  assert.match(content, /--- 转写片段评论 ---/);
});
