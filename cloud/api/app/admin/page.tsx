import Link from 'next/link';

import { readAdminSessionState } from '@/lib/admin-auth';
import { loadAdminDashboardData } from '@/lib/admin-management';
import { prisma } from '@/lib/db';

import {
  adminLoginAction,
  adminLogoutAction,
  assignLegacyWorkspaceAction,
  createInviteCodeAction,
  createManagedUserAction,
  resetManagedUserPasswordAction,
  revokeInviteCodeAction,
} from './actions';

export const dynamic = 'force-dynamic';

function firstSearchParam(value: string | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0] ?? '';
  }

  return value ?? '';
}

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

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const message = firstSearchParam(params.message);
  const error = firstSearchParam(params.error);
  const session = await readAdminSessionState();
  const dashboard = session.authenticated ? await loadAdminDashboardData(prisma) : null;
  const usersWithoutWorkspace = dashboard?.users.filter((user) => !user.workspace) ?? [];

  return (
    <main className="page-shell">
      <div className="admin-shell">
        <section className="glass-card">
          <div className="admin-topbar">
            <div>
              <div className="pill">
                <span className="dot" />
                Piedras Admin
              </div>
              <h1 className="admin-title">邀请码与账号管理后台</h1>
              <p className="muted admin-subtitle">
                这个页面用于管理邀请码、测试账号、legacy 数据接管，以及密码重置。
              </p>
            </div>
            <div className="admin-topbar-actions">
              <Link className="ghost-link" href="/">
                返回云端首页
              </Link>
              {session.authenticated ? (
                <form action={adminLogoutAction}>
                  <button className="secondary-button" type="submit">
                    退出后台
                  </button>
                </form>
              ) : null}
            </div>
          </div>
        </section>

        {message ? <section className="glass-card success-banner">{message}</section> : null}
        {error ? <section className="glass-card error-banner">{error}</section> : null}

        {!session.configured ? (
          <section className="glass-card">
            <h2 className="section-title">先补管理员密钥</h2>
            <p className="muted">
              当前环境还没有配置 <code>ADMIN_API_SECRET</code>，所以内部邀请码接口和管理后台都还不能工作。
            </p>
            <pre className="admin-pre">
{`vercel env add ADMIN_API_SECRET production
vercel env add ADMIN_API_SECRET preview
vercel env add ADMIN_API_SECRET development`}
            </pre>
          </section>
        ) : null}

        {session.configured && !session.authenticated ? (
          <section className="glass-card admin-form-card">
            <h2 className="section-title">管理员登录</h2>
            <p className="muted">使用和内部 API 相同的管理员密钥进入后台。</p>
            <form action={adminLoginAction} className="admin-form-grid">
              <label className="field-block">
                <span>管理员密钥</span>
                <input name="secret" type="password" placeholder="输入 ADMIN_API_SECRET" />
              </label>
              <button className="primary-button" type="submit">
                进入后台
              </button>
            </form>
          </section>
        ) : null}

        {session.authenticated && dashboard ? (
          <>
            <section className="card-grid">
              <article className="glass-card">
                <p className="muted small-label">账号 Schema</p>
                <h2 className="section-number">{dashboard.schema.ready ? 'Ready' : 'Pending'}</h2>
                <p className="muted">
                  {dashboard.schema.ready
                    ? '当前数据库已经具备账号、会话和邀请码表'
                    : `缺失：${dashboard.schema.missingItems.join('、')}`}
                </p>
              </article>

              <article className="glass-card">
                <p className="muted small-label">账号数</p>
                <h2 className="section-number">{dashboard.users.length}</h2>
                <p className="muted">已创建并可管理的账号数量</p>
              </article>

              <article className="glass-card">
                <p className="muted small-label">Legacy 工作区</p>
                <h2 className="section-number">{dashboard.legacyWorkspaces.length}</h2>
                <p className="muted">尚未挂到账号下的历史数据空间</p>
              </article>

              <article className="glass-card">
                <p className="muted small-label">邀请码</p>
                <h2 className="section-number">{dashboard.inviteCodes.length}</h2>
                <p className="muted">已生成的邀请码总数</p>
              </article>
            </section>

            {!dashboard.schema.ready ? (
              <section className="glass-card">
                <h2 className="section-title">数据库还没落库</h2>
                <p className="muted">
                  现在代码已经支持账号体系，但当前环境数据库还没同步到最新 schema。先把下面命令跑完，再回来刷新这个页面。
                </p>
                <pre className="admin-pre">
{`vercel env pull .env.admin --environment=production
set -a; source .env.admin; set +a
npx prisma db push`}
                </pre>
              </section>
            ) : (
              <section className="admin-split-grid">
                <article className="glass-card admin-form-card">
                  <h2 className="section-title">创建托管账号</h2>
                  <p className="muted">
                    直接生成一个账号，可选把某个 legacy 工作区一并交给它。这样你就能拿到保留原始数据的测试账号。
                  </p>
                  <form action={createManagedUserAction} className="admin-form-grid">
                    <label className="field-block">
                      <span>邮箱</span>
                      <input name="email" type="email" placeholder="tester@example.com" required />
                    </label>
                    <label className="field-block">
                      <span>密码</span>
                      <input name="password" type="text" placeholder="至少 8 位" required />
                    </label>
                    <label className="field-block">
                      <span>昵称</span>
                      <input name="displayName" type="text" placeholder="内部识别用，可选" />
                    </label>
                    <label className="field-block">
                      <span>接管 legacy 工作区</span>
                      <select name="legacyWorkspaceId" defaultValue="">
                        <option value="">不接管，创建默认私有空间</option>
                        {dashboard.legacyWorkspaces.map((workspace) => (
                          <option key={workspace.id} value={workspace.id}>
                            {workspace.name} · {workspace.meetingCount} 条录音
                          </option>
                        ))}
                      </select>
                    </label>
                    <button className="primary-button" type="submit">
                      创建账号
                    </button>
                  </form>
                </article>

                <article className="glass-card admin-form-card">
                  <h2 className="section-title">生成邀请码</h2>
                  <p className="muted">以后不需要再手写 curl 了，直接在这里生成即可。</p>
                  <form action={createInviteCodeAction} className="admin-form-grid">
                    <label className="field-block">
                      <span>备注</span>
                      <input name="note" type="text" placeholder="例如：第二轮内测" />
                    </label>
                    <label className="field-block">
                      <span>指定邀请码</span>
                      <input name="code" type="text" placeholder="留空则自动生成" />
                    </label>
                    <button className="primary-button" type="submit">
                      生成邀请码
                    </button>
                  </form>
                </article>

                <article className="glass-card admin-form-card">
                  <h2 className="section-title">把 legacy 数据交给已有账号</h2>
                  <p className="muted">
                    仅支持还没有 workspace 的账号。当前模型是每个账号一个 workspace。
                  </p>
                  <form action={assignLegacyWorkspaceAction} className="admin-form-grid">
                    <label className="field-block">
                      <span>legacy 工作区</span>
                      <select name="workspaceId" defaultValue="">
                        <option value="" disabled>
                          选择一个未认领的数据空间
                        </option>
                        {dashboard.legacyWorkspaces.map((workspace) => (
                          <option key={workspace.id} value={workspace.id}>
                            {workspace.name} · {workspace.meetingCount} 条录音
                          </option>
                        ))}
                      </select>
                    </label>
                    <label className="field-block">
                      <span>目标账号</span>
                      <select name="userId" defaultValue="">
                        <option value="" disabled>
                          选择一个还没 workspace 的账号
                        </option>
                        {usersWithoutWorkspace.map((user) => (
                          <option key={user.id} value={user.id}>
                            {user.email}
                          </option>
                        ))}
                      </select>
                    </label>
                    <button
                      className="secondary-button"
                      type="submit"
                      disabled={dashboard.legacyWorkspaces.length === 0 || usersWithoutWorkspace.length === 0}
                    >
                      接管 legacy 数据
                    </button>
                  </form>
                </article>
              </section>
            )}

            <section className="glass-card">
              <h2 className="section-title">Legacy 工作区现状</h2>
              <div className="admin-table-wrap">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>工作区</th>
                      <th>录音数</th>
                      <th>最新录音</th>
                      <th>创建时间</th>
                    </tr>
                  </thead>
                  <tbody>
                    {dashboard.legacyWorkspaces.length === 0 ? (
                      <tr>
                        <td colSpan={4} className="empty-cell">
                          当前没有待接管的 legacy 工作区
                        </td>
                      </tr>
                    ) : (
                      dashboard.legacyWorkspaces.map((workspace) => (
                        <tr key={workspace.id}>
                          <td>
                            <div className="table-primary">{workspace.name}</div>
                            <div className="table-secondary mono-text">{workspace.id}</div>
                          </td>
                          <td>{workspace.meetingCount}</td>
                          <td>{formatDateTime(workspace.latestMeetingAt)}</td>
                          <td>{formatDateTime(workspace.createdAt)}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </section>

            <section className="glass-card">
              <h2 className="section-title">账号列表</h2>
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
                        <td colSpan={5} className="empty-cell">
                          还没有账号
                        </td>
                      </tr>
                    ) : (
                      dashboard.users.map((user) => (
                        <tr key={user.id}>
                          <td>
                            <div className="table-primary">{user.email}</div>
                            <div className="table-secondary">
                              {user.displayName || '未设置昵称'}
                            </div>
                          </td>
                          <td>
                            {user.workspace ? (
                              <>
                                <div className="table-primary">{user.workspace.name}</div>
                                <div className="table-secondary">
                                  {user.workspace.meetingCount} 条录音
                                </div>
                              </>
                            ) : (
                              <span className="muted">暂无工作区</span>
                            )}
                          </td>
                          <td>{user.authSessionCount}</td>
                          <td>{formatDateTime(user.createdAt)}</td>
                          <td>
                            <form action={resetManagedUserPasswordAction} className="inline-action-form">
                              <input name="userId" type="hidden" value={user.id} />
                              <input
                                name="password"
                                type="text"
                                placeholder="新密码"
                                minLength={8}
                                required
                              />
                              <button className="secondary-button" type="submit">
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

            <section className="glass-card">
              <h2 className="section-title">邀请码列表</h2>
              <div className="admin-table-wrap">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>邀请码</th>
                      <th>备注</th>
                      <th>状态</th>
                      <th>使用者</th>
                      <th>操作</th>
                    </tr>
                  </thead>
                  <tbody>
                    {dashboard.inviteCodes.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="empty-cell">
                          还没有邀请码
                        </td>
                      </tr>
                    ) : (
                      dashboard.inviteCodes.map((inviteCode) => (
                        <tr key={inviteCode.id}>
                          <td className="mono-text">{inviteCode.code}</td>
                          <td>{inviteCode.note || '—'}</td>
                          <td>
                            {inviteCode.isRevoked
                              ? '已停用'
                              : inviteCode.redeemedAt
                                ? '已使用'
                                : '可用'}
                          </td>
                          <td>{inviteCode.redeemedByUser?.email ?? '—'}</td>
                          <td>
                            <form action={revokeInviteCodeAction}>
                              <input name="inviteCodeId" type="hidden" value={inviteCode.id} />
                              <button
                                className="secondary-button"
                                type="submit"
                                disabled={inviteCode.isRevoked || Boolean(inviteCode.redeemedAt)}
                              >
                                停用
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
      </div>
    </main>
  );
}
