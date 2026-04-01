import type { LlmPreset, LlmSettings } from './types.ts';

export interface AiHubMixPresetConfig {
  label: string;
  description: string;
  baseUrl: string;
  path: string;
  defaultModel: string;
  modelHint: string;
}

export const AIHUBMIX_PRESETS: Record<Exclude<LlmPreset, 'custom'>, AiHubMixPresetConfig> = {
  aihubmix: {
    label: 'AiHubMix',
    description: 'LLM 聚合网关，使用 OpenAI 兼容 Chat Completions 接口。',
    baseUrl: 'https://aihubmix.com/v1',
    path: '/chat/completions',
    defaultModel: 'gemini-3-flash-preview',
    modelHint: '填模型市场里的 model id，例如 gemini-3-flash-preview',
  },
};

export const DEFAULT_LLM_SETTINGS: LlmSettings = {
  provider: 'aihubmix',
  preset: 'aihubmix',
  apiKey: '',
  model: AIHUBMIX_PRESETS.aihubmix.defaultModel,
  baseUrl: AIHUBMIX_PRESETS.aihubmix.baseUrl,
  path: AIHUBMIX_PRESETS.aihubmix.path,
};

export function inferLlmPreset(baseUrl?: string): LlmPreset {
  const normalized = (baseUrl || '').trim().toLowerCase().replace(/\/+$/, '');
  if (!normalized) return DEFAULT_LLM_SETTINGS.preset;
  if (normalized.includes('aihubmix.com')) return 'aihubmix';
  return 'custom';
}

export function normalizeAiHubMixPath(path?: string): string {
  const trimmed = (path || '').trim();
  if (!trimmed) return '/chat/completions';
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
}

export function getLlmPresetConfig(preset: LlmPreset): AiHubMixPresetConfig {
  if (preset === 'custom') {
    return {
      label: '自定义兼容接口',
      description: '适用于任意兼容 OpenAI Chat Completions 的服务。',
      baseUrl: DEFAULT_LLM_SETTINGS.baseUrl,
      path: DEFAULT_LLM_SETTINGS.path,
      defaultModel: DEFAULT_LLM_SETTINGS.model,
      modelHint: '填写服务商要求的模型名称',
    };
  }

  return AIHUBMIX_PRESETS[preset];
}

export function applyLlmPreset(
  preset: LlmPreset,
  currentApiKey = ''
): Pick<LlmSettings, 'preset' | 'apiKey' | 'baseUrl' | 'path' | 'model'> {
  const config = getLlmPresetConfig(preset);
  return {
    preset,
    apiKey: currentApiKey,
    baseUrl: config.baseUrl,
    path: config.path,
    model: config.defaultModel,
  };
}

export function normalizeLlmSettings(input?: Partial<LlmSettings>): LlmSettings {
  const merged = {
    ...DEFAULT_LLM_SETTINGS,
    ...input,
  };
  const preset =
    input?.preset && ['aihubmix', 'custom'].includes(input.preset)
      ? input.preset
      : inferLlmPreset(input?.baseUrl);

  return {
    ...merged,
    preset,
    baseUrl: (merged.baseUrl || DEFAULT_LLM_SETTINGS.baseUrl).trim(),
    path: normalizeAiHubMixPath(merged.path),
    model: (merged.model || getLlmPresetConfig(preset).defaultModel).trim(),
  };
}
