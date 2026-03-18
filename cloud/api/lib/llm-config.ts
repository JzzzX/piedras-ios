import type { LlmSettings, OpenAICompatiblePreset } from './types';

export interface OpenAICompatiblePresetConfig {
  label: string;
  description: string;
  baseUrl: string;
  path: string;
  defaultModel: string;
  modelHint: string;
}

export const OPENAI_COMPATIBLE_PRESETS: Record<
  Exclude<OpenAICompatiblePreset, 'custom'>,
  OpenAICompatiblePresetConfig
> = {
  aihubmix: {
    label: 'AiHubMix',
    description: 'LLM 聚合网关，使用 OpenAI 兼容 Chat Completions 接口。',
    baseUrl: 'https://aihubmix.com/v1',
    path: '/chat/completions',
    defaultModel: 'gpt-4o-mini',
    modelHint: '填模型市场里的 model id，例如 gpt-4o-mini',
  },
  openai: {
    label: 'OpenAI 官方',
    description: '直接请求 OpenAI 官方兼容接口。',
    baseUrl: 'https://api.openai.com/v1',
    path: '/chat/completions',
    defaultModel: 'gpt-4.1-mini',
    modelHint: '例如 gpt-4.1-mini',
  },
};

export const DEFAULT_LLM_SETTINGS: LlmSettings = {
  provider: 'auto',
  minimaxApiKey: '',
  minimaxGroupId: '',
  minimaxModel: 'MiniMax-Text-01',
  openaiPreset: 'aihubmix',
  openaiApiKey: '',
  openaiModel: OPENAI_COMPATIBLE_PRESETS.aihubmix.defaultModel,
  openaiBaseUrl: OPENAI_COMPATIBLE_PRESETS.aihubmix.baseUrl,
  openaiPath: OPENAI_COMPATIBLE_PRESETS.aihubmix.path,
};

export function inferOpenAIPreset(baseUrl?: string): OpenAICompatiblePreset {
  const normalized = (baseUrl || '').trim().toLowerCase().replace(/\/+$/, '');
  if (!normalized) return DEFAULT_LLM_SETTINGS.openaiPreset;
  if (normalized.includes('aihubmix.com')) return 'aihubmix';
  if (normalized === 'https://api.openai.com/v1') return 'openai';
  return 'custom';
}

export function normalizeOpenAIPath(path?: string): string {
  const trimmed = (path || '').trim();
  if (!trimmed) return '/chat/completions';
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
}

export function getOpenAIPresetConfig(preset: OpenAICompatiblePreset): OpenAICompatiblePresetConfig {
  if (preset === 'custom') {
    return {
      label: '自定义兼容接口',
      description: '适用于任意兼容 OpenAI Chat Completions 的服务。',
      baseUrl: DEFAULT_LLM_SETTINGS.openaiBaseUrl,
      path: DEFAULT_LLM_SETTINGS.openaiPath,
      defaultModel: DEFAULT_LLM_SETTINGS.openaiModel,
      modelHint: '填写服务商要求的模型名称',
    };
  }

  return OPENAI_COMPATIBLE_PRESETS[preset];
}

export function applyOpenAIPreset(
  preset: OpenAICompatiblePreset,
  currentApiKey = ''
): Pick<LlmSettings, 'openaiPreset' | 'openaiApiKey' | 'openaiBaseUrl' | 'openaiPath' | 'openaiModel'> {
  const config = getOpenAIPresetConfig(preset);
  return {
    openaiPreset: preset,
    openaiApiKey: currentApiKey,
    openaiBaseUrl: config.baseUrl,
    openaiPath: config.path,
    openaiModel: config.defaultModel,
  };
}

export function normalizeLlmSettings(input?: Partial<LlmSettings>): LlmSettings {
  const merged = {
    ...DEFAULT_LLM_SETTINGS,
    ...input,
  };
  const openaiPreset =
    input?.openaiPreset && ['aihubmix', 'openai', 'custom'].includes(input.openaiPreset)
      ? input.openaiPreset
      : inferOpenAIPreset(input?.openaiBaseUrl);

  return {
    ...merged,
    openaiPreset,
    openaiBaseUrl: (merged.openaiBaseUrl || DEFAULT_LLM_SETTINGS.openaiBaseUrl).trim(),
    openaiPath: normalizeOpenAIPath(merged.openaiPath),
    openaiModel: (merged.openaiModel || getOpenAIPresetConfig(openaiPreset).defaultModel).trim(),
  };
}
