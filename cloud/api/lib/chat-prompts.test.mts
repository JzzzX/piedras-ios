import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildGlobalChatSystemPrompt,
  buildMeetingChatSystemPrompt,
  normalizePromptOptions,
} from './chat-prompts.ts';

test('buildMeetingChatSystemPrompt enforces grounded answer order and evidence priority', () => {
  const prompt = buildMeetingChatSystemPrompt(
    normalizePromptOptions({
      meetingType: '通用',
      outputStyle: '平衡',
      includeActionItems: true,
    }),
    '请重点关注发布时间。'
  );

  assert.match(prompt, /先直接回答结论，再补充依据/);
  assert.match(prompt, /用户笔记 > 主笔记附件资料 > AI 会议纪要 > 会议转写 > 转写片段评论/);
  assert.match(prompt, /若证据不足，请明确说明缺少哪类信息/);
  assert.match(prompt, /当前任务 Recipe 指令：请重点关注发布时间。/);
});

test('buildGlobalChatSystemPrompt keeps citation requirement and forbids unsupported claims', () => {
  const prompt = buildGlobalChatSystemPrompt(
    normalizePromptOptions({
      meetingType: '通用',
      outputStyle: '详细',
      includeActionItems: false,
    })
  );

  assert.match(prompt, /只能使用提供的检索内容回答/);
  assert.match(prompt, /先直接回答结论，再给出来源依据/);
  assert.match(prompt, /如果检索内容不足以回答，请明确说明不足/);
  assert.match(prompt, /回答中尽量在关键结论后标注来源编号/);
});
