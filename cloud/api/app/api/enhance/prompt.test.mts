import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildEnhanceSystemPrompt,
  normalizeEnhancePromptOptions,
} from './prompt.ts';

test('访谈类型 prompt 使用访谈专属结构并要求自动识别行动项', () => {
  const prompt = buildEnhanceSystemPrompt(
    normalizeEnhancePromptOptions({
      meetingType: '访谈',
      outputStyle: '平衡',
      includeActionItems: true,
    })
  );

  assert.match(prompt, /## 受访者核心观点/);
  assert.match(prompt, /## 关键引述（原话）/);
  assert.match(prompt, /## 洞察与解读/);
  assert.match(prompt, /## 待跟进问题/);
  assert.doesNotMatch(prompt, /## 关键讨论点/);
  assert.match(prompt, /在信息完整和阅读效率之间保持平衡/);
  assert.match(prompt, /必须引用原话/);
  assert.match(prompt, /若转写和笔记中确实没有任何待办意图，完全省略行动项章节/);
  assert.match(prompt, /整个行动项章节必须放在笔记最末尾/);
});

test('演讲与头脑风暴类型使用不同的章节结构', () => {
  const speechPrompt = buildEnhanceSystemPrompt(
    normalizeEnhancePromptOptions({
      meetingType: '演讲',
      outputStyle: '详细',
      includeActionItems: true,
    })
  );
  const brainstormPrompt = buildEnhanceSystemPrompt(
    normalizeEnhancePromptOptions({
      meetingType: '头脑风暴',
      outputStyle: '行动导向',
      includeActionItems: true,
    })
  );

  assert.match(speechPrompt, /## 核心论点/);
  assert.match(speechPrompt, /## 关键数据与案例/);
  assert.match(speechPrompt, /## 结论与启示/);
  assert.match(speechPrompt, /## 值得深入的方向/);
  assert.doesNotMatch(speechPrompt, /## 创意汇总/);

  assert.match(brainstormPrompt, /## 创意汇总/);
  assert.match(brainstormPrompt, /## 共识与分歧/);
  assert.match(brainstormPrompt, /## 下一步/);
  assert.doesNotMatch(brainstormPrompt, /## 核心论点/);
  assert.match(brainstormPrompt, /优先输出可执行结论/);
});

test('通用类型保留通用结构且 recipe prompt 会置于前面', () => {
  const prompt = buildEnhanceSystemPrompt(
    normalizeEnhancePromptOptions({
      meetingType: '通用',
      outputStyle: '简洁',
      includeActionItems: false,
    }),
    '你必须先输出一句自定义说明。'
  );

  assert.match(prompt, /^你必须先输出一句自定义说明。/);
  assert.match(prompt, /## 会议摘要/);
  assert.match(prompt, /## 关键讨论点/);
  assert.match(prompt, /## 决策事项/);
  assert.match(prompt, /## 待确认事项/);
  assert.match(prompt, /摘要独特性检验/);
  assert.match(prompt, /表达尽量精炼，优先输出结论和关键点/);
  assert.match(prompt, /完全省略行动项章节/);
});
