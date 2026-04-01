import type { LlmRuntimeConfig } from './types.ts';
import { DEFAULT_LLM_SETTINGS, normalizeAiHubMixPath } from './llm-config.ts';

export type LlmProvider = 'aihubmix';

export interface LlmTextContentPart {
  type: 'text';
  text: string;
}

export interface LlmAudioContentPart {
  type: 'audio';
  mimeType: string;
  data: string;
}

export interface LlmFileAudioContentPart {
  type: 'file_audio';
  mimeType: string;
  fileUri: string;
}

export type LlmContentPart =
  | LlmTextContentPart
  | LlmAudioContentPart
  | LlmFileAudioContentPart;

export interface LlmMessage {
  role: 'system' | 'user' | 'assistant';
  content: string | LlmContentPart[];
}

export interface LlmGenerateInput {
  messages: LlmMessage[];
  temperature?: number;
  maxTokens?: number;
  reasoningEffort?: 'low' | 'medium' | 'high';
  preferredProvider?: LlmProvider;
  runtimeConfig?: LlmRuntimeConfig;
  timeoutMs?: number;
  retries?: number;
  allowedProviders?: LlmProvider[];
}

export interface LlmGenerateOutput {
  provider: LlmProvider;
  content: string;
}

interface AiHubMixConfig {
  apiKey: string;
  model: string;
  baseUrl: string;
  path: string;
}

interface AiHubMixResponsePayload {
  choices?: Array<{
    finish_reason?: string | null;
    message?: {
      content?: unknown;
      reasoning_content?: unknown;
    };
  }>;
}

const DEFAULT_TIMEOUT_MS = 18_000;
const DEFAULT_RETRIES = 0;
const AIHUBMIX_PROVIDER = 'aihubmix' as const;

function truncate(text: string, max = 320): string {
  return text.length <= max ? text : `${text.slice(0, max)}...`;
}

function formatHttpError(status: number, body: string): string {
  const category =
    status === 401 || status === 403
      ? '鉴权失败'
      : status === 429
        ? '限流'
        : status >= 500
          ? '上游服务异常'
          : '请求异常';
  const detail = truncate((body || '').replace(/\s+/g, ' ').trim());
  return `AiHubMix ${category}（HTTP ${status}）${detail ? `: ${detail}` : ''}`;
}

function readAiHubMixEnv(key: string, fallback = ''): string {
  return (process.env[key] || fallback).trim();
}

function isRuntimeConfigReady(runtimeConfig?: LlmRuntimeConfig): boolean {
  if (!runtimeConfig || runtimeConfig.provider !== AIHUBMIX_PROVIDER) {
    return false;
  }

  return Boolean(runtimeConfig.apiKey || readAiHubMixEnv('AIHUBMIX_API_KEY'));
}

function getAiHubMixConfig(input: LlmGenerateInput): AiHubMixConfig {
  const runtime =
    input.runtimeConfig?.provider === AIHUBMIX_PROVIDER ? input.runtimeConfig : undefined;

  return {
    apiKey: runtime?.apiKey || readAiHubMixEnv('AIHUBMIX_API_KEY'),
    model:
      runtime?.model
      || readAiHubMixEnv('AIHUBMIX_MODEL', DEFAULT_LLM_SETTINGS.model),
    baseUrl: (
      runtime?.baseUrl
      || readAiHubMixEnv('AIHUBMIX_BASE_URL', DEFAULT_LLM_SETTINGS.baseUrl)
    ).replace(/\/+$/, ''),
    path: normalizeAiHubMixPath(
      runtime?.path || readAiHubMixEnv('AIHUBMIX_PATH', DEFAULT_LLM_SETTINGS.path)
    ),
  };
}

export function getConfiguredProviders(): LlmProvider[] {
  const explicitProvider = String(process.env.LLM_PROVIDER || '').trim().toLowerCase();
  if (explicitProvider && explicitProvider !== AIHUBMIX_PROVIDER) {
    return [];
  }

  return readAiHubMixEnv('AIHUBMIX_API_KEY') ? [AIHUBMIX_PROVIDER] : [];
}

export function hasAvailableLlm(runtimeConfig?: LlmRuntimeConfig): boolean {
  if (isRuntimeConfigReady(runtimeConfig)) {
    return true;
  }

  return getConfiguredProviders().length > 0;
}

function resolveProviderOrder(
  runtimeConfig?: LlmRuntimeConfig,
  allowedProviders?: LlmProvider[]
): LlmProvider[] {
  if (allowedProviders && !allowedProviders.includes(AIHUBMIX_PROVIDER)) {
    return [];
  }

  if (runtimeConfig && runtimeConfig.provider !== AIHUBMIX_PROVIDER) {
    return [];
  }

  return hasAvailableLlm(runtimeConfig) ? [AIHUBMIX_PROVIDER] : [];
}

function normalizeMessageParts(content: string | LlmContentPart[]): LlmContentPart[] {
  if (typeof content === 'string') {
    return [{ type: 'text', text: content }];
  }

  return content;
}

function mapAudioMimeTypeToAiHubMixFormat(mimeType: string): 'wav' | 'mp3' {
  const normalized = mimeType.trim().toLowerCase();
  if (normalized === 'audio/wav' || normalized === 'audio/x-wav' || normalized === 'audio/wave') {
    return 'wav';
  }
  if (normalized === 'audio/mpeg' || normalized === 'audio/mp3') {
    return 'mp3';
  }

  throw new Error(`AiHubMix 音频输入暂不支持 ${mimeType}`);
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`请求超时（>${timeoutMs}ms）`));
    }, timeoutMs);

    promise
      .then((result) => {
        clearTimeout(timer);
        resolve(result);
      })
      .catch((err) => {
        clearTimeout(timer);
        reject(err);
      });
  });
}

function isRetryableProviderError(message: string): boolean {
  const normalized = message.trim().toLowerCase();

  return (
    normalized.includes('请求超时') ||
    normalized.includes('timeout') ||
    normalized.includes('timed out') ||
    normalized.includes('network') ||
    normalized.includes('fetch failed') ||
    normalized.includes('econnreset') ||
    normalized.includes('econnrefused') ||
    normalized.includes('socket hang up') ||
    normalized.includes('http 429') ||
    normalized.includes('限流') ||
    normalized.includes('http 5') ||
    normalized.includes('上游服务异常') ||
    normalized.includes('返回了截断正文') ||
    normalized.includes('返回了不可用正文')
  );
}

function extractText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((part) => extractText(part)).join('');
  }
  if (content && typeof content === 'object') {
    if ('text' in content) {
      const text = (content as { text?: unknown }).text;
      if (typeof text === 'string') return text;
    }
    if ('content' in content) {
      return extractText((content as { content?: unknown }).content);
    }
    if ('parts' in content) {
      return extractText((content as { parts?: unknown }).parts);
    }
  }

  return '';
}

function isUnusableText(text: string): boolean {
  const normalized = text.trim().toLowerCase();
  if (!normalized) return true;

  return ['thought', 'analysis', 'reasoning', 'thinking'].includes(normalized);
}

function validateAiHubMixContent(content: string, finishReason: string | null | undefined) {
  const trimmed = content.trim();
  if (!trimmed || isUnusableText(trimmed)) {
    throw new Error('AiHubMix 返回了不可用正文');
  }

  if (finishReason === 'length') {
    throw new Error('AiHubMix 返回了截断正文');
  }

  return trimmed;
}

async function callAiHubMix(input: LlmGenerateInput): Promise<string> {
  const { apiKey, model, baseUrl, path } = getAiHubMixConfig(input);
  if (!apiKey) {
    throw new Error('AIHUBMIX_API_KEY 未配置');
  }

  const requestBody: Record<string, unknown> = {
    model,
    messages: input.messages.map((message) => ({
      role: message.role,
      content:
        typeof message.content === 'string'
          ? message.content
          : normalizeMessageParts(message.content).map((part) => {
              if (part.type === 'text') {
                return {
                  type: 'text',
                  text: part.text,
                };
              }

              if (part.type === 'audio') {
                return {
                  type: 'input_audio',
                  input_audio: {
                    data: part.data,
                    format: mapAudioMimeTypeToAiHubMixFormat(part.mimeType),
                  },
                };
              }

              throw new Error('AiHubMix 当前不支持 file_audio 输入');
            }),
    })),
    temperature: input.temperature ?? 0.5,
    max_tokens: input.maxTokens ?? 4096,
    reasoning_effort: input.reasoningEffort ?? 'low',
  };

  const res = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(requestBody),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(formatHttpError(res.status, errorText));
  }

  const data = (await res.json()) as AiHubMixResponsePayload;
  const choice = data.choices?.[0];
  const content = extractText(choice?.message?.content);
  return validateAiHubMixContent(content, choice?.finish_reason);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function generateTextWithFallback(
  input: LlmGenerateInput
): Promise<LlmGenerateOutput> {
  const timeoutMs = Number(input.timeoutMs ?? process.env.LLM_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);
  const retries = Number(input.retries ?? process.env.LLM_RETRIES ?? DEFAULT_RETRIES);
  const providers = resolveProviderOrder(input.runtimeConfig, input.allowedProviders);

  if (providers.length === 0) {
    throw new Error('未配置可用 LLM Provider');
  }

  const errors: string[] = [];
  const attempts = Math.max(1, retries + 1);

  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const content = await withTimeout(callAiHubMix(input), timeoutMs);
      return { provider: AIHUBMIX_PROVIDER, content };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      errors.push(`${AIHUBMIX_PROVIDER}#${attempt}: ${message}`);
      if (attempt < attempts && isRetryableProviderError(message)) {
        await sleep(300 * attempt);
        continue;
      }

      break;
    }
  }

  throw new Error(`全部 Provider 调用失败：${errors.join(' | ')}`);
}

export async function probeConfiguredLlm(timeoutMs = 6_000): Promise<{ provider: LlmProvider }> {
  const providers = resolveProviderOrder(undefined, undefined);
  if (providers.length === 0) {
    throw new Error('未配置可用 LLM Provider');
  }

  const probeInput: LlmGenerateInput = {
    messages: [{ role: 'user', content: '请只回复 OK，不要解释。' }],
    temperature: 0,
    maxTokens: 128,
    reasoningEffort: 'low',
  };

  try {
    const content = await withTimeout(callAiHubMix(probeInput), timeoutMs);
    if (content !== 'OK') {
      throw new Error(`AiHubMix 返回了不可用正文：${content}`);
    }

    return { provider: AIHUBMIX_PROVIDER };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`LLM 连通性检查失败：${AIHUBMIX_PROVIDER}: ${message}`);
  }
}
