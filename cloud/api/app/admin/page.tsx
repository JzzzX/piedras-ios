import { getAsrRuntimeStatus } from '@/lib/asr';
import { readAdminSessionState } from '@/lib/admin-auth';
import { loadAdminDashboardData } from '@/lib/admin-management';
import { prisma } from '@/lib/db';
import { getConfiguredProviders } from '@/lib/llm-provider';

import { AdminConsole } from './AdminConsole';

export const dynamic = 'force-dynamic';

async function getDatabaseReachable() {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

function firstSearchParam(value: string | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0] ?? '';
  }

  return value ?? '';
}

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const message = firstSearchParam(params.message);
  const error = firstSearchParam(params.error);
  const [asr, databaseReachable, session] = await Promise.all([
    getAsrRuntimeStatus().catch(() => null),
    getDatabaseReachable(),
    readAdminSessionState(),
  ]);
  const llmProviders = getConfiguredProviders();
  const dashboard = session.authenticated ? await loadAdminDashboardData(prisma) : null;

  return (
    <main className="admin-page-shell">
      <AdminConsole
        message={message}
        error={error}
        session={session}
        dashboard={dashboard}
        runtime={{
          asr,
          databaseReachable,
          llmProviders,
        }}
      />
    </main>
  );
}
