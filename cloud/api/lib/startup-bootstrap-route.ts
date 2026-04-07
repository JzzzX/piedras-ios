import { requireStartupBootstrapReady } from './startup-bootstrap-guard.ts';
import type { StartupBootstrapSnapshot } from './startup-bootstrap-state.ts';

interface StartupBootstrapRouteContext {
  requestId: string;
  route: string;
}

export async function runWithStartupBootstrapGuard(
  context: StartupBootstrapRouteContext,
  handler: () => Promise<Response> | Response,
  snapshot?: StartupBootstrapSnapshot | Partial<StartupBootstrapSnapshot>
): Promise<Response> {
  const startupGuard = requireStartupBootstrapReady(context, snapshot);
  if (startupGuard) {
    return startupGuard;
  }

  return await handler();
}
