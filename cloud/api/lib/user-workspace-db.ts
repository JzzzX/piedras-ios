import type { Prisma, PrismaClient, Workspace } from '@prisma/client';

const DEFAULT_WORKSPACE_NAME = '椰子面试';
const DEFAULT_WORKSPACE_DESCRIPTION = '椰子面试账号默认私有空间';
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
    where: { ownerUserId: input.userId },
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

interface CreateWorkspaceForUserInput {
  userId: string;
  name: string;
  description?: string;
  icon?: string;
  color?: string;
  workflowMode?: Prisma.WorkspaceCreateInput['workflowMode'];
  modeLabel?: string;
}

export async function createWorkspaceForUser(
  db: WorkspaceDatabase,
  input: CreateWorkspaceForUserInput
) {
  const lastWorkspace = await db.workspace.findFirst({
    where: { ownerUserId: input.userId },
    orderBy: { sortOrder: 'desc' },
    select: { sortOrder: true },
  });

  return db.workspace.create({
    data: {
      name: input.name.trim(),
      description: input.description?.trim() || '',
      icon: input.icon?.trim() || DEFAULT_WORKSPACE_ICON,
      color: input.color?.trim() || '#94a3b8',
      workflowMode: input.workflowMode === 'interview' ? 'interview' : 'general',
      modeLabel: input.modeLabel?.trim() || '',
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
