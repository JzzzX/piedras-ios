import type { LlmRuntimeConfig } from './types';
import { DEFAULT_LLM_SETTINGS, normalizeOpenAIPath } from './llm-config';

export type LlmProvider = 'gemini' | 'minimax' | 'openai';

export interface LlmMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LlmGenerateInput {
  messages: LlmMessage[];
  temperature?: number;
  maxTokens?: number;
  reasoningEffort?: 'low' | 'medium' | 'high';
  preferredProvider?: LlmProvider;
  runtimeConfig?: LlmRuntimeConfig;
}

export interface LlmGenerateOutput {
  provider: LlmProvider;
  content: string;
}

const DEFAULT_TIMEOUT_MS = 25_000;
const DEFAULT_RETRIES = 1;

type ProviderName = 'Gemini' | 'MiniMax' | 'OpenAI';

function truncate(text: string, max = 320): string {
  return text.length <= max ? text : `${text.slice(0, max)}...`;
}

function formatHttpError(provider: ProviderName, status: number, body: string): string {
  const category =
    status === 401 || status === 403
      ? '鉴权失败'
      : status === 429
        ? '限流'
        : status >= 500
          ? '上游服务异常'
          : '请求异常';
  const detail = truncate((body || '').replace(/\s+/g, ' ').trim());
  return `${provider} ${category}（HTTP ${status}）${detail ? `: ${detail}` : ''}`;
}

function parseProviderList(value?: string): LlmProvider[] {
  if (!value) return [];
  const providers = value
    .split(',')
    .map((v) => v.trim().toLowerCase())
    .filter(Boolean) as LlmProvider[];
  return Array.from(new Set(providers)).filter((p) =>
    ['gemini', 'minimax', 'openai'].includes(p)
  );
}

function isProviderConfigured(provider: LlmProvider): boolean {
  if (provider === 'gemini') return Boolean(process.env.GEMINI_API_KEY);
  if (provider === 'minimax') {
    return Boolean(process.env.MINIMAX_API_KEY && process.env.MINIMAX_GROUP_ID);
  }
  if (provider === 'openai') return Boolean(process.env.OPENAI_API_KEY);
  return false;
}

function isRuntimeConfigReady(runtimeConfig?: LlmRuntimeConfig): boolean {
  if (!runtimeConfig || runtimeConfig.provider === 'auto') return false;
  if (runtimeConfig.provider === 'minimax') {
    return Boolean(
      (runtimeConfig.apiKey || process.env.MINIMAX_API_KEY) &&
        (runtimeConfig.groupId || process.env.MINIMAX_GROUP_ID)
    );
  }
  if (runtimeConfig.provider === 'openai') {
    return Boolean(
      (runtimeConfig.apiKey || process.env.OPENAI_API_KEY) &&
        (runtimeConfig.model || process.env.OPENAI_MODEL)
    );
  }
  return false;
}

function getGeminiConfig() {
  return {
    apiKey: process.env.GEMINI_API_KEY || '',
    model: process.env.GEMINI_MODEL || 'gemini-flash-latest',
  };
}

function getMiniMaxConfig(input: LlmGenerateInput) {
  const runtime =
    input.runtimeConfig?.provider === 'minimax' ? input.runtimeConfig : undefined;

  return {
    apiKey: runtime?.apiKey || process.env.MINIMAX_API_KEY || '',
    groupId: runtime?.groupId || process.env.MINIMAX_GROUP_ID || '',
    model: runtime?.model || process.env.MINIMAX_MODEL || 'MiniMax-Text-01',
  };
}

function getOpenAIConfig(input: LlmGenerateInput) {
  const runtime =
    input.runtimeConfig?.provider === 'openai' ? input.runtimeConfig : undefined;

  return {
    apiKey: runtime?.apiKey || process.env.OPENAI_API_KEY || '',
    model: runtime?.model || process.env.OPENAI_MODEL || DEFAULT_LLM_SETTINGS.openaiModel,
    baseUrl:
      (runtime?.baseUrl || process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1').replace(
        /\/+$/,
        ''
      ),
    path: normalizeOpenAIPath(runtime?.path || process.env.OPENAI_PATH || '/chat/completions'),
  };
}

export function getConfiguredProviders(): LlmProvider[] {
  const explicit = parseProviderList(process.env.LLM_PROVIDER);
  if (explicit.length > 0) {
    return explicit.filter(isProviderConfigured);
  }

  const preferredOrder: LlmProvider[] = ['gemini', 'minimax', 'openai'];
  return preferredOrder.filter(isProviderConfigured);
}

export function hasAvailableLlm(runtimeConfig?: LlmRuntimeConfig): boolean {
  if (isRuntimeConfigReady(runtimeConfig)) {
    return true;
  }

  return getConfiguredProviders().length > 0;
}

function resolveProviderOrder(
  preferredProvider?: LlmProvider,
  runtimeConfig?: LlmRuntimeConfig
): LlmProvider[] {
  if (runtimeConfig && runtimeConfig.provider !== 'auto') {
    return [runtimeConfig.provider];
  }

  const configured = getConfiguredProviders();
  if (configured.length === 0) return [];

  const fallbackProviders = parseProviderList(process.env.LLM_FALLBACKS);

  if (preferredProvider && configured.includes(preferredProvider)) {
    const fallback = fallbackProviders.filter(
      (p) => p !== preferredProvider && configured.includes(p)
    );
    const rest = configured.filter(
      (p) => p !== preferredProvider && !fallback.includes(p)
    );
    return [preferredProvider, ...fallback, ...rest];
  }

  if (fallbackProviders.length === 0) return configured;

  const primary = configured[0];
  const fallback = fallbackProviders.filter(
    (p) => p !== primary && configured.includes(p)
  );
  const rest = configured.filter((p) => p !== primary && !fallback.includes(p));
  return [primary, ...fallback, ...rest];
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

async function callGemini(input: LlmGenerateInput): Promise<string> {
  const { apiKey, model } = getGeminiConfig();
  if (!apiKey) throw new Error('GEMINI_API_KEY 未配置');
  const system = input.messages.find((m) => m.role === 'system')?.content;
  const conversation = input.messages.filter((m) => m.role !== 'system');

  const contents =
    conversation.length > 0
      ? conversation.map((m) => ({
          role: m.role === 'assistant' ? 'model' : 'user',
          parts: [{ text: m.content }],
        }))
      : [{ role: 'user', parts: [{ text: '请根据系统指令开始回答。' }] }];

  const body: Record<string, unknown> = {
    contents,
    generationConfig: {
      temperature: input.temperature ?? 0.5,
      maxOutputTokens: input.maxTokens ?? 4096,
    },
  };

  if (system) {
    body.systemInstruction = { parts: [{ text: system }] };
  }

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
  );

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(formatHttpError('Gemini', res.status, errorText));
  }

  const data = await res.json();
  const content = (data.candidates?.[0]?.content?.parts || [])
    .map((p: { text?: string }) => p.text || '')
    .join('')
    .trim();

  if (!content) {
    throw new Error('Gemini 返回为空');
  }

  return content;
}

function extractOpenAIContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (content && typeof content === 'object') {
    if ('text' in content) {
      const text = (content as { text?: unknown }).text;
      if (typeof text === 'string') return text;
    }
    if ('parts' in content) {
      return extractOpenAIContent((content as { parts?: unknown }).parts);
    }
    if ('content' in content) {
      return extractOpenAIContent((content as { content?: unknown }).content);
    }
    return '';
  }
  if (!Array.isArray(content)) return '';

  return content
    .map((part) => {
      return extractOpenAIContent(part);
    })
    .join('');
}

function isGemini3Model(model: string): boolean {
  return /^gemini-3(?:[.-]|$)/i.test(model.trim());
}

async function callOpenAI(input: LlmGenerateInput): Promise<string> {
  const { apiKey, model, baseUrl, path } = getOpenAIConfig(input);
  if (!apiKey) {
    throw new Error('OPENAI_API_KEY 未配置');
  }

  const requestBody: Record<string, unknown> = {
    model,
    messages: input.messages,
    temperature: input.temperature ?? 0.5,
    max_tokens: input.maxTokens ?? 4096,
  };

  if (input.reasoningEffort) {
    requestBody.reasoning_effort = input.reasoningEffort;
  } else if (isGemini3Model(model)) {
    requestBody.reasoning_effort = 'low';
  }

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
    throw new Error(formatHttpError('OpenAI', res.status, errorText));
  }

  const data = await res.json();
  const content = extractOpenAIContent(data.choices?.[0]?.message?.content).trim();
  if (!content) {
    throw new Error('OpenAI 返回为空');
  }

  return content;
}

interface MiniMaxPayload {
  choices?: Array<{
    delta?: { content?: unknown };
    message?: { content?: unknown };
    text?: string;
  }>;
  reply?: string;
  base_resp?: {
    status_code?: number;
    status_msg?: string;
  };
}

function extractTextFromUnknownContent(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') return part;
        if (part && typeof part === 'object' && 'text' in part) {
          const text = (part as { text?: unknown }).text;
          return typeof text === 'string' ? text : '';
        }
        return '';
      })
      .join('');
  }
  return '';
}

function extractMiniMaxText(payload: MiniMaxPayload): string {
  if (typeof payload.reply === 'string' && payload.reply.trim()) {
    return payload.reply;
  }

  const parts: string[] = [];
  for (const choice of payload.choices || []) {
    const delta = extractTextFromUnknownContent(choice.delta?.content);
    const message = extractTextFromUnknownContent(choice.message?.content);
    const text = typeof choice.text === 'string' ? choice.text : '';
    if (delta) parts.push(delta);
    if (message) parts.push(message);
    if (text) parts.push(text);
  }
  return parts.join('');
}

async function callMiniMaxNonStream(input: LlmGenerateInput): Promise<string> {
  const { apiKey, groupId, model } = getMiniMaxConfig(input);
  if (!apiKey || !groupId) {
    throw new Error('MiniMax 凭证未配置');
  }

  const res = await fetch(
    `https://api.minimax.chat/v1/text/chatcompletion_v2?GroupId=${groupId}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        stream: false,
        messages: input.messages,
        temperature: input.temperature ?? 0.5,
        max_tokens: input.maxTokens ?? 4096,
      }),
    }
  );

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(formatHttpError('MiniMax', res.status, errorText));
  }

  const data = (await res.json()) as MiniMaxPayload;

  if (data.base_resp?.status_code && data.base_resp.status_code !== 0) {
    throw new Error(
      `MiniMax 上游异常（${data.base_resp.status_code}）：${data.base_resp.status_msg || '未知错误'}`
    );
  }

  const content = extractMiniMaxText(data).trim();
  if (!content) throw new Error('MiniMax 返回为空');
  return content;
}

async function callMiniMaxStream(input: LlmGenerateInput): Promise<string> {
  const { apiKey, groupId, model } = getMiniMaxConfig(input);
  if (!apiKey || !groupId) {
    throw new Error('MiniMax 凭证未配置');
  }

  const res = await fetch(
    `https://api.minimax.chat/v1/text/chatcompletion_v2?GroupId=${groupId}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        stream: true,
        messages: input.messages,
        temperature: input.temperature ?? 0.5,
        max_tokens: input.maxTokens ?? 4096,
      }),
    }
  );

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(formatHttpError('MiniMax', res.status, errorText));
  }

  if (!res.body) {
    throw new Error('MiniMax 流式响应为空');
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let fullText = '';
  let doneSeen = false;
  let invalidJsonCount = 0;

  const processEvent = (rawEvent: string): void => {
    if (!rawEvent.trim()) return;

    const lines = rawEvent.split(/\r?\n/);
    const dataLines = lines
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice(5).trimStart());

    if (dataLines.length === 0) return;

    const dataText = dataLines.join('\n').trim();
    if (!dataText) return;

    if (dataText === '[DONE]') {
      doneSeen = true;
      return;
    }

    let payload: MiniMaxPayload;
    try {
      payload = JSON.parse(dataText) as MiniMaxPayload;
    } catch {
      invalidJsonCount += 1;
      return;
    }

    if (payload.base_resp?.status_code && payload.base_resp.status_code !== 0) {
      throw new Error(
        `MiniMax 上游异常（${payload.base_resp.status_code}）：${payload.base_resp.status_msg || '未知错误'}`
      );
    }

    const delta = extractMiniMaxText(payload);
    if (delta) {
      fullText += delta;
    }
  };

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      buffer = buffer.replace(/\r/g, '');

      let separatorIndex = buffer.indexOf('\n\n');
      while (separatorIndex !== -1) {
        const eventText = buffer.slice(0, separatorIndex);
        buffer = buffer.slice(separatorIndex + 2);
        processEvent(eventText);
        separatorIndex = buffer.indexOf('\n\n');
      }
    }

    buffer += decoder.decode();
    buffer = buffer.replace(/\r/g, '');
    if (buffer.trim()) {
      processEvent(buffer);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`MiniMax 流式读取失败：${message}`);
  }

  const content = fullText.trim();
  if (content) {
    return content;
  }

  if (invalidJsonCount > 0) {
    throw new Error(`MiniMax 流式解析失败：收到 ${invalidJsonCount} 条非法 JSON 片段`);
  }

  if (!doneSeen) {
    throw new Error('MiniMax 流式连接中断：未收到完成信号');
  }

  throw new Error('MiniMax 流式返回为空');
}

async function callMiniMax(input: LlmGenerateInput): Promise<string> {
  if (process.env.MINIMAX_USE_STREAM === 'false') {
    return callMiniMaxNonStream(input);
  }

  let streamError = '';
  try {
    return await callMiniMaxStream(input);
  } catch (error) {
    streamError = error instanceof Error ? error.message : String(error);
  }

  try {
    return await callMiniMaxNonStream(input);
  } catch (fallbackError) {
    const fallbackMessage =
      fallbackError instanceof Error ? fallbackError.message : String(fallbackError);
    throw new Error(
      `MiniMax 流式与非流式均失败；流式错误：${streamError}；非流式错误：${fallbackMessage}`
    );
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function generateTextWithFallback(
  input: LlmGenerateInput
): Promise<LlmGenerateOutput> {
  const timeoutMs = Number(process.env.LLM_TIMEOUT_MS || DEFAULT_TIMEOUT_MS);
  const retries = Number(process.env.LLM_RETRIES || DEFAULT_RETRIES);
  const providers = resolveProviderOrder(input.preferredProvider, input.runtimeConfig);

  if (providers.length === 0) {
    throw new Error('未配置可用 LLM Provider');
  }

  const errors: string[] = [];

  for (const provider of providers) {
    const attempts = Math.max(1, retries + 1);
    for (let attempt = 1; attempt <= attempts; attempt++) {
      try {
        const content = await withTimeout(
          provider === 'gemini'
            ? callGemini(input)
            : provider === 'minimax'
              ? callMiniMax(input)
              : callOpenAI(input),
          timeoutMs
        );

        return { provider, content };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        errors.push(`${provider}#${attempt}: ${message}`);
        if (attempt < attempts) {
          await sleep(300 * attempt);
        }
      }
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
    maxTokens: 32,
    reasoningEffort: 'low',
  };

  const errors: string[] = [];

  for (const provider of providers) {
    try {
      await withTimeout(
        provider === 'gemini'
          ? callGemini(probeInput)
          : provider === 'minimax'
            ? callMiniMax(probeInput)
            : callOpenAI(probeInput),
        timeoutMs
      );

      return { provider };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      errors.push(`${provider}: ${message}`);
    }
  }

  throw new Error(`LLM 连通性检查失败：${errors.join(' | ')}`);
}
