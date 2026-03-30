export type StartupBootstrapStatus = 'idle' | 'running' | 'ready' | 'failed';

export interface StartupBootstrapSnapshot {
  ready: boolean;
  status: StartupBootstrapStatus;
  attempts: number;
  startedAt: string | null;
  completedAt: string | null;
  lastError: string | null;
  schemaReady: boolean;
  missingItems: string[];
  legacyUsers: string[];
  retryScheduled: boolean;
  retryAt: string | null;
}

export const STARTUP_BOOTSTRAP_GLOBAL_KEY = '__PIEDRAS_STARTUP_BOOTSTRAP_STATE__';

export function buildStartupBootstrapSnapshot(
  input: Partial<StartupBootstrapSnapshot> = {}
): StartupBootstrapSnapshot {
  return {
    ready: input.ready ?? false,
    status: input.status ?? 'idle',
    attempts: input.attempts ?? 0,
    startedAt: input.startedAt ?? null,
    completedAt: input.completedAt ?? null,
    lastError: input.lastError ?? null,
    schemaReady: input.schemaReady ?? false,
    missingItems: [...(input.missingItems ?? [])],
    legacyUsers: [...(input.legacyUsers ?? [])],
    retryScheduled: input.retryScheduled ?? false,
    retryAt: input.retryAt ?? null,
  };
}

export function getStartupBootstrapSnapshot(): StartupBootstrapSnapshot {
  const state = (globalThis as Record<string, unknown>)[STARTUP_BOOTSTRAP_GLOBAL_KEY] as
    | Partial<StartupBootstrapSnapshot>
    | undefined;

  return buildStartupBootstrapSnapshot(state);
}
