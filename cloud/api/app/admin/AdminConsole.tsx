import type { readAdminSessionState } from '@/lib/admin-auth';
import type { loadAdminDashboardData } from '@/lib/admin-management';

import {
  adminLoginAction,
  adminLogoutAction,
  resetManagedUserPasswordAction,
} from './actions';

type AdminSessionState = Awaited<ReturnType<typeof readAdminSessionState>>;
type AdminDashboardData = Awaited<ReturnType<typeof loadAdminDashboardData>>;

type AdminRuntimeSummary = {
  databaseReachable: boolean;
  llmProviders: string[];
  asr: {
    configured?: boolean;
    ready?: boolean;
    message?: string;
  } | null;
};

function formatDateTime(value: Date | string | null | undefined) {
  if (!value) {
    return '—';
  }

  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }

  return new Intl.DateTimeFormat('zh-CN', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

function runtimeCards(runtime: AdminRuntimeSummary) {
  const llmTitle = runtime.llmProviders.length > 0 ? runtime.llmProviders.join(', ') : 'Unconfigured';
  const llmDescription =
    runtime.llmProviders.length > 0 ? '当前云端启用的 AiHubMix 模型链路。' : '当前没有可用的云端大模型链路。';

  const asrTitle = runtime.asr?.ready ? 'Ready' : runtime.asr?.configured ? 'Configured' : 'Unconfigured';
  const asrDescription = runtime.asr?.message ?? '未完成 ASR 状态检查。';

  return [
    {
      label: 'Database',
      value: runtime.databaseReachable ? 'Online' : 'Offline',
      description: `PostgreSQL ${runtime.databaseReachable ? '已连通' : '未连通'}。`,
    },
    {
      label: 'LLM',
      value: llmTitle,
      description: llmDescription,
    },
    {
      label: 'ASR',
      value: asrTitle,
      description: asrDescription,
    },
  ];
}

export function AdminConsole({
  dashboardError,
  message,
  error,
  session,
  dashboard,
  runtime,
}: {
  dashboardError: string;
  message: string;
  error: string;
  session: AdminSessionState;
  dashboard: AdminDashboardData | null;
  runtime: AdminRuntimeSummary;
}) {
  const cards = runtimeCards(runtime);

  return (
    <section className="admin-shell">
      <section className="admin-panel admin-panel-hero">
        <div className="admin-panel-header">
          <div>
            <div className="admin-eyebrow">Piedras Cloud</div>
            <h1 className="admin-title">最小账号后台</h1>
            <p className="admin-subtitle">这里只保留管理员登录、账号列表、服务摘要和密码重置。</p>
          </div>
          <div className="admin-header-actions">
            <a className="admin-text-link" href="/">
              返回首页
            </a>
            {session.authenticated ? (
              <form action={adminLogoutAction}>
                <button className="admin-secondary-button" type="submit">
                  退出后台
                </button>
              </form>
            ) : null}
          </div>
        </div>
      </section>

      {message ? <section className="admin-banner admin-banner-success">{message}</section> : null}
      {error ? <section className="admin-banner admin-banner-error">{error}</section> : null}
      {dashboardError ? (
        <section className="admin-banner admin-banner-error">
          {dashboardError || '后台数据加载失败，请稍后重试'}
        </section>
      ) : null}

      {!session.configured ? (
        <section className="admin-panel">
          <h2 className="admin-section-title">未配置管理员密钥</h2>
          <p className="admin-muted">
            当前环境尚未设置 <code>ADMIN_API_SECRET</code>，所以这个后台暂时不能登录。
          </p>
        </section>
      ) : null}

      {session.configured && !session.authenticated ? (
        <section className="admin-panel admin-login-panel">
          <h2 className="admin-section-title">管理员登录</h2>
          <p className="admin-muted">输入管理员密钥后进入最小账号后台。</p>
          <form action={adminLoginAction} className="admin-form-grid">
            <label className="admin-field">
              <span>管理员密钥</span>
              <input name="secret" type="password" placeholder="输入 ADMIN_API_SECRET" />
            </label>
            <button className="admin-primary-button" type="submit">
              进入后台
            </button>
          </form>
        </section>
      ) : null}

      {session.authenticated && dashboard ? (
        <>
          <section className="admin-summary-grid">
            <article className="admin-panel admin-summary-card">
              <p className="admin-card-label">账号 Schema</p>
              <h2 className="admin-card-value">{dashboard.schema.ready ? 'Ready' : 'Pending'}</h2>
              <p className="admin-muted">
                {dashboard.schema.ready
                  ? '当前数据库已经具备账号和会话的关键结构。'
                  : `缺失：${dashboard.schema.missingItems.join('、')}`}
              </p>
            </article>

            <article className="admin-panel admin-summary-card">
              <p className="admin-card-label">账号数</p>
              <h2 className="admin-card-value">{dashboard.users.length}</h2>
              <p className="admin-muted">当前已创建且可管理的账号数量。</p>
            </article>

            {cards.map((card) => (
              <article key={card.label} className="admin-panel admin-summary-card">
                <p className="admin-card-label">{card.label}</p>
                <h2 className="admin-card-value">{card.value}</h2>
                <p className="admin-muted">{card.description}</p>
              </article>
            ))}
          </section>

          <section className="admin-panel">
            <div className="admin-list-header">
              <div>
                <h2 className="admin-section-title">账号列表</h2>
                <p className="admin-muted">可以查看账号基本信息，并直接重置密码。</p>
              </div>
            </div>

            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>账号</th>
                    <th>工作区</th>
                    <th>登录会话</th>
                    <th>创建时间</th>
                    <th>密码重置</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.users.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="admin-empty-cell">
                        还没有账号。
                      </td>
                    </tr>
                  ) : (
                    dashboard.users.map((user) => (
                      <tr key={user.id}>
                        <td>
                          <div className="admin-table-primary">{user.email}</div>
                          <div className="admin-table-secondary">{user.displayName || '未设置昵称'}</div>
                        </td>
                        <td>
                          {user.workspace ? (
                            <>
                              <div className="admin-table-primary">{user.workspace.name}</div>
                              <div className="admin-table-secondary">{user.workspace.meetingCount} 条录音</div>
                            </>
                          ) : (
                            <span className="admin-muted">暂无工作区</span>
                          )}
                        </td>
                        <td>{user.authSessionCount}</td>
                        <td>{formatDateTime(user.createdAt)}</td>
                        <td>
                          <form action={resetManagedUserPasswordAction} className="admin-inline-form">
                            <input name="userId" type="hidden" value={user.id} />
                            <input
                              name="password"
                              type="text"
                              placeholder="新密码"
                              minLength={8}
                              required
                            />
                            <button className="admin-secondary-button" type="submit">
                              重置
                            </button>
                          </form>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </>
      ) : null}
    </section>
  );
}
