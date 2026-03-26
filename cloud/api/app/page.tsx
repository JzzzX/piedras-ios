import { getAsrRuntimeStatus } from "@/lib/asr";
import { readAdminSessionState } from "@/lib/admin-auth";
import { loadAdminDashboardData } from "@/lib/admin-management";
import { prisma } from "@/lib/db";
import { getConfiguredProviders } from "@/lib/llm-provider";
import { AdminConsole } from "./admin/AdminConsole";

export const dynamic = "force-dynamic";

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
    return value[0] ?? "";
  }

  return value ?? "";
}

export default async function HomePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const message = firstSearchParam(params.message);
  const error = firstSearchParam(params.error);
  const [asr, dbReachable, session] = await Promise.all([
    getAsrRuntimeStatus().catch(() => null),
    getDatabaseReachable(),
    readAdminSessionState(),
  ]);
  const llmProviders = getConfiguredProviders();
  const dashboard = session.authenticated ? await loadAdminDashboardData(prisma) : null;

  return (
    <main className="page-shell">
      <div className="admin-shell">
        <section className="glass-card">
          <div className="pill">
            <span className="dot" />
            Piedras Cloud
          </div>
          <h1 style={{ margin: "16px 0 10px", fontSize: 34 }}>piedras-ios 单主仓云端入口</h1>
          <p className="muted" style={{ margin: 0, lineHeight: 1.7 }}>
            当前目录只承载 iOS 真实依赖的 API 和状态调试页，不再承载旧 Web 工作台。
          </p>
        </section>

        <section className="card-grid">
          <article className="glass-card">
            <p className="muted" style={{ marginTop: 0 }}>Database</p>
            <h2 style={{ margin: "0 0 6px", fontSize: 24 }}>{dbReachable ? "Online" : "Offline"}</h2>
            <p className="muted" style={{ margin: 0 }}>
              PostgreSQL {dbReachable ? "已连通" : "未连通"}
            </p>
          </article>

          <article className="glass-card">
            <p className="muted" style={{ marginTop: 0 }}>LLM</p>
            <h2 style={{ margin: "0 0 6px", fontSize: 24 }}>
              {llmProviders.length > 0 ? llmProviders.join(", ") : "Unconfigured"}
            </h2>
            <p className="muted" style={{ margin: 0 }}>
              当前云端优先 provider 列表
            </p>
          </article>

          <article className="glass-card">
            <p className="muted" style={{ marginTop: 0 }}>ASR</p>
            <h2 style={{ margin: "0 0 6px", fontSize: 24 }}>
              {asr?.ready ? "Ready" : asr?.configured ? "Configured" : "Unconfigured"}
            </h2>
            <p className="muted" style={{ margin: 0 }}>
              {asr?.message ?? "未完成 ASR 状态检查"}
            </p>
          </article>
        </section>

        <section className="glass-card">
          <p className="muted" style={{ marginTop: 0 }}>Useful Endpoints</p>
          <ul className="endpoint-list">
            <li><a href="/healthz">/healthz</a></li>
            <li><a href="/api/llm/status">/api/llm/status</a></li>
            <li><a href="/api/asr/status">/api/asr/status</a></li>
            <li><a href="/api/workspaces">/api/workspaces</a></li>
            <li><a href="/admin">/admin</a></li>
            <li><a href="#account-admin">账号管理区</a></li>
          </ul>
        </section>

        <AdminConsole
          message={message}
          error={error}
          session={session}
          dashboard={dashboard}
        />
      </div>
    </main>
  );
}
