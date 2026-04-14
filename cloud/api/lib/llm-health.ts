import { DEFAULT_LLM_SETTINGS, inferLlmPreset } from './llm-config.ts';
import {
  getConfiguredProviders,
  hasAvailableLlm,
  probeConfiguredLlm,
  type LlmProvider,
} from './llm-provider.ts';
import { toErrorMessage } from './runtime-health.ts';

export interface LlmRuntimeStatus {
  configured: boolean;
  reachable: boolean;
  ready: boolean;
  checkedAt: string | null;
  lastError: string | null;
  provider: LlmProvider | 'none';
  model: string | null;
  preset: string | null;
  message: string;
}

interface LlmRuntimeHealthConfig {
  probeTimeoutMs: number;
  successTtlMs: number;
  failureTtlMs: number;
}

interface CachedLlmProbeStatus {
  reachable: boolean;
  checkedAt: string;
  lastError: string | null;
  provider: LlmProvider;
}

type LlmProbeCacheEntry = {
  expiresAt: number;
  value: CachedLlmProbeStatus;
};

export function resolveLlmRuntimeHealthConfig(): LlmRuntimeHealthConfig {
  return {
    probeTimeoutMs: Number(process.env.LLM_STATUS_PROBE_TIMEOUT_MS || 3_000),
    successTtlMs: Number(process.env.LLM_STATUS_SUCCESS_TTL_MS || 300_000),
    failureTtlMs: Number(process.env.LLM_STATUS_FAILURE_TTL_MS || 30_000),
  };
}

function getLlmProbeCache(): Map<string, LlmProbeCacheEntry> {
  const globalScope = globalThis as typeof globalThis & {
    __cocoInterviewLlmProbeCache?: Map<string, LlmProbeCacheEntry>;
  };

  if (!globalScope.__cocoInterviewLlmProbeCache) {
    globalScope.__cocoInterviewLlmProbeCache = new Map();
  }

  return globalScope.__cocoInterviewLlmProbeCache;
}

async function getCachedLlmProbeStatus(
  key: string,
  config: LlmRuntimeHealthConfig,
  resolver: () => Promise<CachedLlmProbeStatus>
): Promise<CachedLlmProbeStatus> {
  const cache = getLlmProbeCache();
  const now = Date.now();
  const cached = cache.get(key);

  if (cached && cached.expiresAt > now) {
    return cached.value;
  }

  const value = await resolver();
  cache.set(key, {
    expiresAt: now + (value.reachable ? config.successTtlMs : config.failureTtlMs),
    value,
  });

  return value;
}

function resolveModel(provider: LlmProvider): string | null {
  switch (provider) {
    case 'aihubmix':
      return process.env.AIHUBMIX_MODEL || DEFAULT_LLM_SETTINGS.model;
  }
}

function resolveMessage(provider: LlmProvider, preset: string | null): string {
  switch (provider) {
    case 'aihubmix':
      if (preset === 'aihubmix') return 'AiHubMix 已配置';
      return '自定义 AiHubMix 兼容接口已配置';
  }
}

export async function getLlmRuntimeStatus(): Promise<LlmRuntimeStatus> {
  if (!hasAvailableLlm()) {
    return {
      configured: false,
      reachable: false,
      ready: false,
      checkedAt: null,
      lastError: '未配置可用 LLM',
      provider: 'none',
      model: null,
      preset: null,
      message: '未配置可用 LLM',
    };
  }

  const configuredProvider = getConfiguredProviders()[0] ?? 'aihubmix';
  const config = resolveLlmRuntimeHealthConfig();
  const probe = await getCachedLlmProbeStatus(
    `llm:${configuredProvider}:${process.env.AIHUBMIX_MODEL || ''}:${process.env.AIHUBMIX_BASE_URL || ''}`,
    config,
    async (): Promise<CachedLlmProbeStatus> => {
      const checkedAt = new Date().toISOString();

      try {
        const result = await probeConfiguredLlm(config.probeTimeoutMs);
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
  const preset =
    provider === 'aihubmix'
      ? inferLlmPreset(process.env.AIHUBMIX_BASE_URL)
      : null;
  const reachable = probe.reachable;

  return {
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
  };
}
