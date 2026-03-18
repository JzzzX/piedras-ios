import { NextRequest, NextResponse } from 'next/server';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import type { PromptOptions } from '@/lib/types';

function normalizePromptOptions(input?: Partial<PromptOptions>): PromptOptions {
  return {
    meetingType: input?.meetingType || '通用',
    outputStyle: input?.outputStyle || '平衡',
    includeActionItems: input?.includeActionItems ?? true,
  };
}

function buildHeuristicTitle(transcript: string): string {
  const plain = transcript
    .replace(/\[[^\]]+\]/g, ' ')
    .replace(/\s+/g, ' ')
    .replace(/[，。！？、,.!?:：；;（）()“”"']/g, ' ')
    .trim();

  if (!plain) return '未命名会议';

  const candidate = plain
    .split(' ')
    .map((part) => part.trim())
    .filter((part) => part.length >= 2)
    .slice(0, 4)
    .join('')
    .slice(0, 18);

  return candidate || plain.slice(0, 18) || '未命名会议';
}

export async function POST(req: NextRequest) {
  try {
    const { transcript, promptOptions, llmRuntimeConfig } = await req.json();
    const normalizedTranscript = (transcript || '').trim();

    if (!normalizedTranscript) {
      return NextResponse.json({ title: '未命名会议', provider: 'demo' });
    }

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      return NextResponse.json({
        title: buildHeuristicTitle(normalizedTranscript),
        provider: 'demo',
      });
    }

    const options = normalizePromptOptions(promptOptions);

    const { content, provider } = await generateTextWithFallback({
      messages: [
        {
          role: 'system',
          content: `你是一位会议标题生成助手。请根据会议转写内容生成一个简短、清晰、可读的中文会议标题。

要求：
1. 只输出标题本身，不要解释。
2. 长度尽量控制在 8-18 个汉字。
3. 不要使用书名号、引号、句号等多余标点。
4. 标题应准确体现会议主题或主要议题。
5. 当前会议类型：${options.meetingType}。`,
        },
        {
          role: 'user',
          content: `请为以下会议内容生成标题：\n\n${normalizedTranscript.slice(0, 3000)}`,
        },
      ],
      temperature: 0.2,
      maxTokens: 80,
      runtimeConfig: llmRuntimeConfig,
    });

    const title = content
      .replace(/[\n\r#>*`]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 32);

    return NextResponse.json({
      title: title || buildHeuristicTitle(normalizedTranscript),
      provider,
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : '自动标题生成失败',
      },
      { status: 500 }
    );
  }
}
