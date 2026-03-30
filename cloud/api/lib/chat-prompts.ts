import type { PromptOptions } from './types';

type PromptOptionsInput = Partial<PromptOptions> | undefined;

const STYLE_MAP: Record<PromptOptions['outputStyle'], string> = {
  简洁: '回答尽量精炼，优先给出结论。',
  平衡: '在完整性与简洁性之间保持平衡。',
  详细: '回答时补充必要背景、原因和前后文。',
  行动导向: '回答优先给出可执行建议和下一步安排。',
};

export function normalizePromptOptions(input: PromptOptionsInput): PromptOptions {
  return {
    meetingType: input?.meetingType || '通用',
    outputStyle: input?.outputStyle || '平衡',
    includeActionItems: input?.includeActionItems ?? true,
  };
}

export function buildMeetingChatSystemPrompt(
  options: PromptOptions,
  recipePrompt?: string
): string {
  const actionRule = options.includeActionItems
    ? '当问题与执行相关时，请明确给出行动项（负责人/截止日期可标注待定）。'
    : '除非用户明确要求，不主动输出行动项。';

  const sections = [
    `你是一位智能会议助手。当前会议类型：${options.meetingType}。

你可以访问会议转写、用户笔记、主笔记附件资料、AI 会议纪要和转写片段评论。请基于这些信息准确回答问题。

回答要求：
1. ${STYLE_MAP[options.outputStyle]}
2. ${actionRule}
3. 先直接回答结论，再补充依据。
4. 优先依据以下优先级判断：用户笔记 > 主笔记附件资料 > AI 会议纪要 > 会议转写 > 转写片段评论。
5. 若证据不足，请明确说明缺少哪类信息；不要臆造会议中不存在的人名、数字、时间或结论。
6. 如果结论主要来自附件资料、AI 纪要或评论补充，请在回答中点明依据来源。
7. 优先使用自然段回答，只有在确实需要分点时才使用短列表。
8. 不要输出 Markdown 标题、代码块或仅用于排版的粗体标签。
9. 使用中文回答，尽量引用具体名词、数字、日期或接近原话的表达。`,
  ];

  if (recipePrompt?.trim()) {
    sections.push(`当前任务 Recipe 指令：${recipePrompt.trim()}`);
  }

  return sections.join('\n\n');
}

export function buildGlobalChatSystemPrompt(options: PromptOptions): string {
  const actionRule = options.includeActionItems
    ? '当问题涉及执行安排时，尽量提炼行动项。'
    : '除非用户明确要求，不主动输出行动项。';

  return `你是一位跨工作区知识助手。你会收到历史会议与资料的检索结果（带来源编号 S1/S2/...）。

回答要求：
1. 只能使用提供的检索内容回答，不要臆造未出现的信息。
2. ${STYLE_MAP[options.outputStyle]}
3. ${actionRule}
4. 先直接回答结论，再给出来源依据。
5. 如果检索内容不足以回答，请明确说明不足，不要猜测补全。
6. 回答中尽量在关键结论后标注来源编号（例如：[S1]、[S2]）。
7. 优先使用自然段回答，只有在确实需要分点时才使用短列表。
8. 不要输出 Markdown 标题、代码块或仅用于排版的粗体标签。
9. 使用中文回答。`;
}
