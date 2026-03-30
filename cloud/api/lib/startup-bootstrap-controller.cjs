const STARTUP_BOOTSTRAP_GLOBAL_KEY = '__PIEDRAS_STARTUP_BOOTSTRAP_STATE__';

function createDefaultState() {
  return {
    ready: false,
    status: 'idle',
    attempts: 0,
    startedAt: null,
    completedAt: null,
    lastError: null,
    schemaReady: false,
    missingItems: [],
    legacyUsers: [],
    retryScheduled: false,
    retryAt: null,
  };
}

function cloneState(state) {
  return {
    ...state,
    missingItems: Array.isArray(state.missingItems) ? [...state.missingItems] : [],
    legacyUsers: Array.isArray(state.legacyUsers) ? [...state.legacyUsers] : [],
  };
}

function getMutableState() {
  if (!globalThis[STARTUP_BOOTSTRAP_GLOBAL_KEY]) {
    globalThis[STARTUP_BOOTSTRAP_GLOBAL_KEY] = createDefaultState();
  }

  return globalThis[STARTUP_BOOTSTRAP_GLOBAL_KEY];
}

function resetStartupBootstrapStateForTests() {
  globalThis[STARTUP_BOOTSTRAP_GLOBAL_KEY] = createDefaultState();
}

function getStartupBootstrapSnapshotForTests() {
  return cloneState(getMutableState());
}

function toISOString(value) {
  if (value instanceof Date) {
    return value.toISOString();
  }

  return new Date(value).toISOString();
}

function collectLegacyUsers(entries) {
  if (!Array.isArray(entries)) {
    return [];
  }

  return entries
    .map((entry) => {
      if (!entry) return null;
      if (typeof entry === 'string') return entry;
      if (typeof entry.email === 'string' && entry.email.trim()) return entry.email.trim();
      if (typeof entry.id === 'string' && entry.id.trim()) return entry.id.trim();
      return null;
    })
    .filter(Boolean);
}

function createStartupBootstrapController({
  bootstrap,
  logger = () => {},
  retryDelayMS = 5_000,
  setTimeoutFn = setTimeout,
  clearTimeoutFn = clearTimeout,
  now = () => new Date(),
}) {
  let inFlightPromise = null;
  let retryHandle = null;

  const clearRetry = () => {
    if (retryHandle) {
      clearTimeoutFn(retryHandle);
      retryHandle = null;
    }

    const state = getMutableState();
    state.retryScheduled = false;
    state.retryAt = null;
  };

  const scheduleRetry = () => {
    if (retryHandle) {
      return;
    }

    const state = getMutableState();
    state.retryScheduled = true;
    state.retryAt = toISOString(new Date(now().getTime() + retryDelayMS));
    retryHandle = setTimeoutFn(async () => {
      retryHandle = null;
      const currentState = getMutableState();
      currentState.retryScheduled = false;
      currentState.retryAt = null;
      await controller.start();
    }, retryDelayMS);
  };

  const controller = {
    async start() {
      if (inFlightPromise) {
        return inFlightPromise;
      }

      clearRetry();

      const state = getMutableState();
      state.ready = false;
      state.status = 'running';
      state.attempts += 1;
      state.startedAt = toISOString(now());
      state.completedAt = null;
      state.lastError = null;
      state.schemaReady = false;
      state.missingItems = [];
      state.legacyUsers = [];

      inFlightPromise = (async () => {
        try {
          const result = await bootstrap();
          const nextState = getMutableState();
          nextState.ready = true;
          nextState.status = 'ready';
          nextState.completedAt = toISOString(now());
          nextState.lastError = null;
          nextState.schemaReady = Boolean(result?.schemaStatus?.ready);
          nextState.missingItems = Array.isArray(result?.schemaStatus?.missingItems)
            ? [...result.schemaStatus.missingItems]
            : [];
          nextState.legacyUsers = collectLegacyUsers(result?.legacyUsers);
          nextState.retryScheduled = false;
          nextState.retryAt = null;

          logger('startup_bootstrap_ready', {
            attempts: nextState.attempts,
            schemaReady: nextState.schemaReady,
            missingItems: nextState.missingItems,
            legacyUsers: nextState.legacyUsers,
          });

          return result;
        } catch (error) {
          const nextState = getMutableState();
          nextState.ready = false;
          nextState.status = 'failed';
          nextState.completedAt = toISOString(now());
          nextState.lastError = error instanceof Error ? error.message : String(error);

          logger('startup_bootstrap_failed', {
            attempts: nextState.attempts,
            error: nextState.lastError,
            retryDelayMS,
          });

          scheduleRetry();
          return null;
        } finally {
          inFlightPromise = null;
        }
      })();

      return inFlightPromise;
    },
    getSnapshot() {
      return cloneState(getMutableState());
    },
    cancelRetry() {
      clearRetry();
    },
  };

  return controller;
}

module.exports = {
  createStartupBootstrapController,
  getStartupBootstrapSnapshotForTests,
  resetStartupBootstrapStateForTests,
};
