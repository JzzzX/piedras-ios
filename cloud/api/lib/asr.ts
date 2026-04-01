import { fetchWithTimeout, getCachedRuntimeHealth, toErrorMessage } from './runtime-health.ts';

export type AsrMode = 'browser' | 'aliyun' | 'doubao';

export interface AsrStatus {
  mode: AsrMode;
  provider: 'web-speech' | 'aliyun' | 'doubao-proxy';
  configured: boolean;
  reachable: boolean;
  ready: boolean;
  missing: string[];
  message: string;
  checkedAt: string | null;
  lastError: string | null;
}

function normalizeProxyPath(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    return '/';
  }

  const withLeadingSlash = trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
  return withLeadingSlash.replace(/\/{2,}/g, '/');
}

export function resolveAsrProxyHealthPath(): string {
  const configuredPath = normalizeProxyPath(process.env.ASR_PROXY_HEALTH_PATH || '/asr-proxy/healthz');
  return configuredPath === '/healthz' ? '/asr-proxy/healthz' : configuredPath;
}

export function resolveAsrProxyWSPath(): string {
  return normalizeProxyPath(process.env.ASR_PROXY_WS_PATH || '/ws/asr');
}

export function getAsrMode(): AsrMode {
  const mode = process.env.ASR_MODE?.toLowerCase();
  if (mode === 'aliyun') return 'aliyun';
  if (mode === 'doubao') return 'doubao';
  return 'browser';
}

export function getAsrStatus(): AsrStatus {
  const mode = getAsrMode();

  if (mode === 'browser') {
    return {
      mode,
      provider: 'web-speech',
      configured: true,
      reachable: true,
      ready: true,
      missing: [],
      message: '使用浏览器 Web Speech API（Demo 模式）',
      checkedAt: null,
      lastError: null,
    };
  }

  if (mode === 'doubao') {
    const hasAppId = Boolean(process.env.DOUBAO_ASR_APP_ID);
    const hasAccessToken = Boolean(process.env.DOUBAO_ASR_ACCESS_TOKEN);
    const hasResourceId = Boolean(process.env.DOUBAO_ASR_RESOURCE_ID);
    const hasProxySecret = Boolean(process.env.ASR_PROXY_SESSION_SECRET);

    const missing: string[] = [];
    if (!hasAppId) {
      missing.push('DOUBAO_ASR_APP_ID');
    }
    if (!hasAccessToken) {
      missing.push('DOUBAO_ASR_ACCESS_TOKEN');
    }
    if (!hasResourceId) {
      missing.push('DOUBAO_ASR_RESOURCE_ID');
    }
    if (!hasProxySecret) {
      missing.push('ASR_PROXY_SESSION_SECRET');
    }

    const configured = missing.length === 0;

    return {
      mode,
      provider: 'doubao-proxy',
      configured,
      reachable: false,
      ready: configured,
      missing,
      message: configured ? '豆包 ASR 代理已配置' : '豆包 ASR 配置不完整，暂不可用',
      checkedAt: null,
      lastError: null,
    };
  }

  const hasAppKey = Boolean(process.env.ALICLOUD_ASR_APP_KEY);
  const hasToken = Boolean(process.env.ALICLOUD_ASR_TOKEN);
  const hasAkSk = Boolean(
    process.env.ALICLOUD_ACCESS_KEY_ID && process.env.ALICLOUD_ACCESS_KEY_SECRET
  );

  const missing: string[] = [];
  if (!hasAppKey) {
    missing.push('ALICLOUD_ASR_APP_KEY');
  }
  if (!hasToken && !hasAkSk) {
    missing.push('ALICLOUD_ASR_TOKEN or (ALICLOUD_ACCESS_KEY_ID + ALICLOUD_ACCESS_KEY_SECRET)');
  }

  const configured = missing.length === 0;

  return {
    mode,
    provider: 'aliyun',
    configured,
    reachable: configured,
    ready: configured,
    missing: [...missing],
    message: configured
      ? hasToken
        ? '已配置阿里云 ASR（直连 Token 模式）'
        : '已配置阿里云 ASR（AK/SK 自动换 Token）'
      : '阿里云 ASR 配置不完整，暂不可用',
    checkedAt: null,
    lastError: null,
  };
}

export function resolveAsrProxyPublicBaseURL(
  fallbackProtocol = process.env.NODE_ENV === 'production' ? 'https' : 'http'
): URL | null {
  const explicitBaseURL = process.env.ASR_PROXY_PUBLIC_BASE_URL?.trim();
  if (explicitBaseURL) {
    try {
      return new URL(explicitBaseURL);
    } catch {
      return null;
    }
  }

  const protocol = (process.env.ASR_PROXY_PUBLIC_PROTOCOL?.trim() || fallbackProtocol)
    .replace(/:$/, '')
    .toLowerCase();
  const host = process.env.ASR_PROXY_PUBLIC_HOST?.trim()
    || (process.env.NODE_ENV == 'production' ? '' : '127.0.0.1');
  if (!host) {
    return null;
  }
  const port = process.env.ASR_PROXY_PUBLIC_PORT?.trim() || process.env.ASR_PROXY_PORT?.trim() || '';
  const defaultPort = protocol === 'http' ? '80' : '443';
  const authority = port && port !== defaultPort ? `${host}:${port}` : host;

  try {
    return new URL(`${protocol}://${authority}`);
  } catch {
    return null;
  }
}

export async function getAsrRuntimeStatus(): Promise<AsrStatus> {
  const configuredStatus = getAsrStatus();
  const checkedAt = new Date().toISOString();

  if (configuredStatus.mode !== 'doubao' || !configuredStatus.configured) {
    return {
      ...configuredStatus,
      reachable: configuredStatus.mode === 'browser' ? true : configuredStatus.configured,
      ready: configuredStatus.mode === 'browser' ? true : configuredStatus.configured,
      checkedAt,
    };
  }

  const proxyBaseURL = resolveAsrProxyPublicBaseURL();
  const cacheKey = `asr:${proxyBaseURL?.toString() || 'missing-proxy-base-url'}:${resolveAsrProxyHealthPath()}`;
  const probe = await getCachedRuntimeHealth(
    cacheKey,
    30_000,
    async (): Promise<{ reachable: boolean; checkedAt: string; lastError: string | null }> => {
      const probeCheckedAt = new Date().toISOString();

      if (!proxyBaseURL) {
        return {
          reachable: false,
          checkedAt: probeCheckedAt,
          lastError: 'ASR_PROXY_PUBLIC_BASE_URL / HOST 未配置',
        };
      }

      const healthURL = new URL(resolveAsrProxyHealthPath(), proxyBaseURL);

      try {
        const response = await fetchWithTimeout(healthURL, { method: 'GET' }, 3_000);
        if (!response.ok) {
          const detail = (await response.text()).trim();
          throw new Error(detail ? `HTTP ${response.status}: ${detail}` : `HTTP ${response.status}`);
        }

        return {
          reachable: true,
          checkedAt: probeCheckedAt,
          lastError: null,
        };
      } catch (error) {
        return {
          reachable: false,
          checkedAt: probeCheckedAt,
          lastError: toErrorMessage(error),
        };
      }
    }
  );

  return {
    ...configuredStatus,
    reachable: probe.reachable,
    ready: configuredStatus.configured && probe.reachable,
    checkedAt: probe.checkedAt,
    lastError: probe.lastError,
    message: probe.reachable
      ? '豆包 ASR 代理在线'
      : `豆包 ASR 代理不可达${probe.lastError ? `：${probe.lastError}` : ''}`,
  };
}
