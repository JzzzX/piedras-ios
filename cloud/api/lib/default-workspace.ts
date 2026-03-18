import { prisma } from './db';

export const DEFAULT_WORKSPACE_ID = '00000000-0000-0000-0000-000000000001';

const DEFAULT_WORKSPACE = {
  id: DEFAULT_WORKSPACE_ID,
  name: '默认空间',
  description: '系统自动创建的默认空间',
  icon: 'folder',
  color: '#94a3b8',
  workflowMode: 'general',
  modeLabel: '',
  sortOrder: 0,
} as const;

export async function ensureDefaultWorkspace() {
  const existing = await prisma.workspace.findFirst({
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  if (existing) {
    return existing;
  }

  return prisma.workspace.upsert({
    where: { id: DEFAULT_WORKSPACE_ID },
    update: {},
    create: DEFAULT_WORKSPACE,
  });
}

export async function resolveWorkspaceId(workspaceId?: string | null) {
  const trimmed = workspaceId?.trim();
  if (trimmed) {
    return trimmed;
  }

  const workspace = await ensureDefaultWorkspace();
  return workspace.id;
}
