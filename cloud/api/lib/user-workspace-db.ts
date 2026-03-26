import type { Prisma, PrismaClient, Workspace } from '@prisma/client';

const DEFAULT_WORKSPACE_NAME = 'Piedras';
const DEFAULT_WORKSPACE_DESCRIPTION = 'Piedras 账号默认私有空间';
const DEFAULT_WORKSPACE_ICON = 'folder';
const DEFAULT_WORKSPACE_COLOR = '#0f766e';

type WorkspaceDatabase = PrismaClient | Prisma.TransactionClient;

function nextSortOrder(lastSortOrder: number | null | undefined) {
  return (lastSortOrder ?? 0) + 1;
}

export async function createDefaultWorkspaceForUser(
  db: WorkspaceDatabase,
  input: { userId: string }
) {
  const lastWorkspace = await db.workspace.findFirst({
    orderBy: { sortOrder: 'desc' },
    select: { sortOrder: true },
  });

  return db.workspace.create({
    data: {
      name: DEFAULT_WORKSPACE_NAME,
      description: DEFAULT_WORKSPACE_DESCRIPTION,
      icon: DEFAULT_WORKSPACE_ICON,
      color: DEFAULT_WORKSPACE_COLOR,
      workflowMode: 'general',
      modeLabel: 'Private',
      sortOrder: nextSortOrder(lastWorkspace?.sortOrder),
      ownerUserId: input.userId,
    },
  });
}

export async function ensureDefaultWorkspaceForUser(
  db: WorkspaceDatabase,
  input: { userId: string }
): Promise<Workspace> {
  const existingWorkspace = await db.workspace.findFirst({
    where: { ownerUserId: input.userId },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  if (existingWorkspace) {
    return existingWorkspace;
  }

  return createDefaultWorkspaceForUser(db, input);
}
