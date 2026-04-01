import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { buildMeetingMaterialContext } from '@/lib/meeting-ai-context';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import {
  buildEnhanceSystemPrompt,
  normalizeEnhancePromptOptions,
} from './prompt';

const ENHANCE_TIMEOUT_MS = 12_000;
const ENHANCE_MAX_TOKENS = 1_200;

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/enhance');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const {
      transcript,
      userNotes,
      meetingTitle,
      segmentCommentsContext,
      noteAttachmentsContext,
      recipePrompt,
      promptOptions,
      llmRuntimeConfig,
    } =
      await req.json();

    const resolvedRecipePrompt = typeof recipePrompt === 'string' ? recipePrompt.trim() : '';

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      // Demo 模式：无 API Key 时返回模拟结果
      return jsonResponse(context, {
        content: generateDemoEnhancedNotes(transcript, userNotes, meetingTitle),
      provider: 'demo',
      });
    }

    const options = normalizeEnhancePromptOptions(promptOptions);
    const systemPrompt = buildEnhanceSystemPrompt(options, resolvedRecipePrompt);

    const { content, provider } = await generateTextWithFallback({
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: `会议标题：${meetingTitle || '未命名会议'}

${buildMeetingMaterialContext({
  transcript,
  userNotes,
  noteAttachmentsContext,
  segmentCommentsContext,
}, {
  transcriptMaxChars: 12_000,
  userNotesMaxChars: 4_000,
  noteAttachmentsMaxChars: 3_000,
  segmentCommentsMaxChars: 3_000,
})}

请根据以上内容生成结构化会议纪要。`,
        },
      ],
      temperature: 0.3,
      maxTokens: ENHANCE_MAX_TOKENS,
      timeoutMs: ENHANCE_TIMEOUT_MS,
      runtimeConfig: llmRuntimeConfig,
    });

    return jsonResponse(context, { content, provider });
  } catch (error) {
    return errorResponse(
      context,
      502,
      error instanceof Error ? `AI 后处理失败：${error.message}` : 'AI 后处理失败，请稍后重试。',
      error
    );
  }
}

function generateDemoEnhancedNotes(
  transcript: string,
  userNotes: string,
  meetingTitle: string
): string {
  return `## 会议摘要
本次「${meetingTitle || '未命名会议'}」讨论了多项重要议题。参会者就关键问题进行了深入交流，并达成了初步共识。

## 关键讨论点
${transcript ? '- 基于转写内容的讨论要点（Demo 模式）' : '- 暂无转写内容'}
${userNotes ? '- 基于用户笔记的重点' : ''}

## 决策事项
- 此为 Demo 模式生成的示例内容
- 配置 AiHubMix API Key 后将使用真实 AI 生成

## 行动项
- [ ] 配置 AiHubMix API Key
- [ ] 配置阿里云 ASR 相关密钥以启用实时转写

## 待确认事项
- 完整 AI 功能需要配置相应的 API 密钥

> *提示：当前为 Demo 模式。配置 .env.local 中的 API 密钥后可启用完整 AI 能力。*`;
}
