import {
  buildStartupBootstrapSnapshot,
  getStartupBootstrapSnapshot,
  type StartupBootstrapSnapshot,
} from './startup-bootstrap-state.ts';

interface StartupBootstrapGuardContext {
  requestId: string;
  route: string;
}

function summarizeMissingItems(items: string[]) {
  if (items.length === 0) {
    return '服务端仍在完成启动初始化。';
  }

  return `服务端仍在完成数据库结构修复：${items.join('、')}。`;
}

export function requireStartupBootstrapReady(
  context: StartupBootstrapGuardContext,
  snapshot: StartupBootstrapSnapshot | Partial<StartupBootstrapSnapshot> = getStartupBootstrapSnapshot()
) {
  const resolvedSnapshot = buildStartupBootstrapSnapshot(snapshot);
  if (resolvedSnapshot.ready && resolvedSnapshot.schemaReady) {
    return null;
  }

  console.warn(
    `[startup-bootstrap-blocked] route=${context.route} requestId=${context.requestId} ` +
      `status=${resolvedSnapshot.status} missingItems=${resolvedSnapshot.missingItems.join(',')}`
  );

  return Response.json(
    {
      error: `云端同步暂不可用，${summarizeMissingItems(resolvedSnapshot.missingItems)}`,
      requestId: context.requestId,
      route: context.route,
    },
    {
      status: 503,
      headers: {
        'X-Request-Id': context.requestId,
      },
    }
  );
}
