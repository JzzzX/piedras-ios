import { NextResponse } from 'next/server';
import { inferOpenAIPreset } from '@/lib/llm-config';
import {
  getConfiguredProviders,
  hasAvailableLlm,
  probeConfiguredLlm,
  type LlmProvider,
} from '@/lib/llm-provider';
import { getCachedRuntimeHealth, toErrorMessage } from '@/lib/runtime-health';

function resolveModel(provider: LlmProvider): string | null {
  switch (provider) {
    case 'openai':
      return process.env.OPENAI_MODEL || 'gpt-4o-mini';
    case 'gemini':
      return process.env.GEMINI_MODEL || 'gemini-flash-latest';
    case 'minimax':
      return process.env.MINIMAX_MODEL || 'MiniMax-Text-01';
  }
}

function resolveMessage(provider: LlmProvider, preset: string | null): string {
  switch (provider) {
    case 'openai':
      if (preset === 'aihubmix') return 'AiHubMix 已配置';
      if (preset === 'openai') return 'OpenAI 兼容接口已配置';
      return '自定义 OpenAI 兼容接口已配置';
    case 'gemini':
      return 'Gemini 已配置';
    case 'minimax':
      return 'MiniMax 已配置';
  }
}

export async function GET() {
  if (!hasAvailableLlm()) {
    return NextResponse.json({
      configured: false,
      reachable: false,
      ready: false,
      checkedAt: null,
      lastError: '未配置可用 LLM',
      provider: 'none',
      model: null,
      preset: null,
      message: '未配置可用 LLM',
    });
  }

  const configuredProvider = getConfiguredProviders()[0] ?? 'openai';
  const probe = await getCachedRuntimeHealth(
    `llm:${configuredProvider}:${process.env.OPENAI_MODEL || ''}:${process.env.OPENAI_BASE_URL || ''}`,
    60_000,
    async (): Promise<{ reachable: boolean; checkedAt: string; lastError: string | null; provider: LlmProvider }> => {
      const checkedAt = new Date().toISOString();

      try {
        const result = await probeConfiguredLlm();
        return {
          reachable: true,
          checkedAt,
          lastError: null,
          provider: result.provider,
        };
      } catch (error) {
        return {
          reachable: false,
          checkedAt,
          lastError: toErrorMessage(error),
          provider: configuredProvider,
        };
      }
    }
  );
  const provider = probe.provider;
  const preset = provider === 'openai' ? inferOpenAIPreset(process.env.OPENAI_BASE_URL) : null;
  const reachable = probe.reachable;

  return NextResponse.json({
    configured: true,
    reachable,
    ready: reachable,
    checkedAt: probe.checkedAt,
    lastError: probe.lastError,
    provider,
    model: resolveModel(provider),
    preset,
    message: reachable
      ? resolveMessage(provider, preset)
      : `LLM 已配置，但连通性检查失败${probe.lastError ? `：${probe.lastError}` : ''}`,
  });
}
