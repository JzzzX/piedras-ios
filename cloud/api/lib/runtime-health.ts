type CacheEntry<T> = {
  expiresAt: number;
  value: T;
};

type RuntimeHealthCache = Map<string, CacheEntry<unknown>>;

function getRuntimeHealthCache(): RuntimeHealthCache {
  const globalScope = globalThis as typeof globalThis & {
    __cocoInterviewRuntimeHealthCache?: RuntimeHealthCache;
  };

  if (!globalScope.__cocoInterviewRuntimeHealthCache) {
    globalScope.__cocoInterviewRuntimeHealthCache = new Map();
  }

  return globalScope.__cocoInterviewRuntimeHealthCache;
}

export async function getCachedRuntimeHealth<T>(
  key: string,
  ttlMs: number,
  resolver: () => Promise<T>
): Promise<T> {
  const cache = getRuntimeHealthCache();
  const now = Date.now();
  const cached = cache.get(key) as CacheEntry<T> | undefined;

  if (cached && cached.expiresAt > now) {
    return cached.value;
  }

  const value = await resolver();
  cache.set(key, {
    expiresAt: now + ttlMs,
    value,
  });

  return value;
}

export async function fetchWithTimeout(
  input: string | URL,
  init: RequestInit = {},
  timeoutMs = 3_000
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    return await fetch(input, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

export function toErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    if (error.name === 'AbortError') {
      return '请求超时';
    }
    return error.message;
  }

  return String(error);
}
