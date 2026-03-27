import { getAsrRuntimeStatus } from '@/lib/asr';
import { prisma } from '@/lib/db';
import { getConfiguredProviders } from '@/lib/llm-provider';

export const dynamic = 'force-dynamic';

async function getDatabaseReachable() {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

function llmSummary(llmProviders: string[]) {
  if (llmProviders.length === 0) {
    return {
      title: 'Unconfigured',
      description: '当前没有可用的云端大模型 provider。',
    };
  }

  return {
    title: llmProviders.join(', '),
    description: '当前云端优先 provider 列表。',
  };
}

function asrSummary(asr: Awaited<ReturnType<typeof getAsrRuntimeStatus>> | null) {
  if (!asr) {
    return {
      title: 'Unknown',
      description: '暂时无法读取语音识别运行状态。',
    };
  }

  if (asr.ready) {
    return {
      title: 'Ready',
      description: asr.message,
    };
  }

  if (asr.configured) {
    return {
      title: 'Configured',
      description: asr.message,
    };
  }

  return {
    title: 'Unconfigured',
    description: asr.message,
  };
}

export default async function HomePage() {
  const [asr, databaseReachable] = await Promise.all([
    getAsrRuntimeStatus().catch(() => null),
    getDatabaseReachable(),
  ]);
  const llmProviders = getConfiguredProviders();
  const llm = llmSummary(llmProviders);
  const asrCard = asrSummary(asr);

  return (
    <main className="home-page-shell">
      <section className="home-hero">
        <div className="home-topbar">
          <div className="home-badge">Piedras Cloud</div>
          <a className="home-admin-link" href="/admin">
            进入后台
          </a>
        </div>

        <div className="home-copy">
          <h1 className="home-title">iOS 录音与转写的云端入口</h1>
          <p className="home-subtitle">
            这里只保留服务状态和必要的调试入口，不再展示旧版后台管理内容。
          </p>
        </div>

        <section className="home-status-grid" aria-label="Cloud runtime status">
          <article className="home-status-card">
            <p className="home-status-label">Database</p>
            <h2 className="home-status-title">{databaseReachable ? 'Online' : 'Offline'}</h2>
            <p className="home-status-description">
              PostgreSQL {databaseReachable ? '已连通' : '未连通'}。
            </p>
          </article>

          <article className="home-status-card">
            <p className="home-status-label">LLM</p>
            <h2 className="home-status-title">{llm.title}</h2>
            <p className="home-status-description">{llm.description}</p>
          </article>

          <article className="home-status-card">
            <p className="home-status-label">ASR</p>
            <h2 className="home-status-title">{asrCard.title}</h2>
            <p className="home-status-description">{asrCard.description}</p>
          </article>
        </section>

        <section className="home-links-panel">
          <p className="home-links-label">常用入口</p>
          <div className="home-links">
            <a href="/healthz">/healthz</a>
            <a href="/api/asr/status">/api/asr/status</a>
            <a href="/api/llm/status">/api/llm/status</a>
            <a href="/admin">/admin</a>
          </div>
        </section>
      </section>
    </main>
  );
}
