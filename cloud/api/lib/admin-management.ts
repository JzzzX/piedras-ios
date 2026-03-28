import type { Prisma, PrismaClient } from '@prisma/client';

import {
  generateInviteCode,
  hashPassword,
  isPasswordValid,
  normalizeEmail,
  normalizeInviteCode,
} from './auth.ts';
import { ensureDefaultWorkspaceForUser } from './user-workspace-db.ts';

type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export class AdminManagementError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export interface AdminSchemaStatus {
  userTable: boolean;
  authSessionTable: boolean;
  inviteCodeTable: boolean;
  workspaceOwnerColumn: boolean;
  ready: boolean;
  missingItems: string[];
}

export interface AdminUserSummary {
  id: string;
  email: string;
  displayName: string;
  createdAt: Date;
  authSessionCount: number;
  workspace: {
    id: string;
    name: string;
    createdAt: Date;
    meetingCount: number;
    collectionCount: number;
    globalChatSessionCount: number;
  } | null;
}

export interface AdminInviteCodeSummary {
  id: string;
  code: string;
  note: string;
  isRevoked: boolean;
  redeemedAt: Date | null;
  createdAt: Date;
  redeemedByUser: {
    id: string;
    email: string;
  } | null;
}

export interface LegacyWorkspaceSummary {
  id: string;
  name: string;
  description: string;
  createdAt: Date;
  meetingCount: number;
  collectionCount: number;
  globalChatSessionCount: number;
  latestMeetingAt: Date | null;
}

interface RawSchemaRow {
  objectName: string;
}

interface RawLegacyWorkspaceRow {
  id: string;
  name: string;
  description: string;
  createdAt: Date;
  meetingCount: bigint | number | null;
  collectionCount: bigint | number | null;
  globalChatSessionCount: bigint | number | null;
  latestMeetingAt: Date | null;
}

function toCount(value: bigint | number | null | undefined) {
  return Number(value ?? 0);
}

async function assertSchemaReady(db: DatabaseClient) {
  const status = await getAdminSchemaStatus(db);
  if (!status.ready) {
    throw new AdminManagementError(
      503,
      `账号 schema 尚未就绪：${status.missingItems.join('、') || '缺少必要字段'}`
    );
  }
}

async function claimLegacyWorkspaceForUser(
  db: DatabaseClient,
  input: {
    workspaceId: string;
    userId: string;
  }
) {
  const workspace = await db.workspace.findFirst({
    where: { id: input.workspaceId },
    select: {
      id: true,
      name: true,
      ownerUserId: true,
    },
  });

  if (!workspace) {
    throw new AdminManagementError(404, '未找到指定的 legacy 工作区');
  }

  if (workspace.ownerUserId) {
    throw new AdminManagementError(409, '该 legacy 工作区已被账号接管');
  }

  const existingOwnedWorkspace = await db.workspace.findFirst({
    where: { ownerUserId: input.userId },
    select: {
      id: true,
      name: true,
    },
  });

  if (existingOwnedWorkspace) {
    throw new AdminManagementError(409, '目标账号已有工作区，不能再接管 legacy 数据');
  }

  return db.workspace.update({
    where: { id: input.workspaceId },
    data: { ownerUserId: input.userId },
    select: {
      id: true,
      name: true,
      createdAt: true,
      _count: {
        select: {
          meetings: true,
          collections: true,
          globalChatSessions: true,
        },
      },
    },
  });
}

export async function getAdminSchemaStatus(db: DatabaseClient): Promise<AdminSchemaStatus> {
  const tables = await db.$queryRawUnsafe<RawSchemaRow[]>(`
    SELECT table_name AS "objectName"
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('User', 'AuthSession', 'InviteCode')
  `);
  const columns = await db.$queryRawUnsafe<RawSchemaRow[]>(`
    SELECT column_name AS "objectName"
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Workspace'
      AND column_name = 'ownerUserId'
  `);

  const tableSet = new Set(tables.map((item) => item.objectName));
  const columnSet = new Set(columns.map((item) => item.objectName));
  const status: AdminSchemaStatus = {
    userTable: tableSet.has('User'),
    authSessionTable: tableSet.has('AuthSession'),
    inviteCodeTable: tableSet.has('InviteCode'),
    workspaceOwnerColumn: columnSet.has('ownerUserId'),
    ready: false,
    missingItems: [],
  };

  if (!status.userTable) {
    status.missingItems.push('User 表');
  }
  if (!status.authSessionTable) {
    status.missingItems.push('AuthSession 表');
  }
  if (!status.inviteCodeTable) {
    status.missingItems.push('InviteCode 表');
  }
  if (!status.workspaceOwnerColumn) {
    status.missingItems.push('Workspace.ownerUserId 字段');
  }

  status.ready = status.missingItems.length === 0;
  return status;
}

export async function listLegacyWorkspaces(
  db: DatabaseClient,
  schemaStatus?: AdminSchemaStatus
): Promise<LegacyWorkspaceSummary[]> {
  const status = schemaStatus ?? (await getAdminSchemaStatus(db));
  const ownershipFilter = status.workspaceOwnerColumn ? 'WHERE w."ownerUserId" IS NULL' : '';
  const rows = await db.$queryRawUnsafe<RawLegacyWorkspaceRow[]>(`
    SELECT
      w.id,
      w.name,
      w.description,
      w."createdAt",
      COUNT(DISTINCT m.id) AS "meetingCount",
      COUNT(DISTINCT c.id) AS "collectionCount",
      COUNT(DISTINCT g.id) AS "globalChatSessionCount",
      MAX(m.date) AS "latestMeetingAt"
    FROM "Workspace" w
    LEFT JOIN "Meeting" m ON m."workspaceId" = w.id
    LEFT JOIN "Folder" c ON c."workspaceId" = w.id
    LEFT JOIN "GlobalChatSession" g ON g."workspaceId" = w.id
    ${ownershipFilter}
    GROUP BY w.id, w.name, w.description, w."createdAt"
    ORDER BY "meetingCount" DESC, w."createdAt" ASC
  `);

  return rows.map((row) => ({
    id: row.id,
    name: row.name,
    description: row.description,
    createdAt: new Date(row.createdAt),
    meetingCount: toCount(row.meetingCount),
    collectionCount: toCount(row.collectionCount),
    globalChatSessionCount: toCount(row.globalChatSessionCount),
    latestMeetingAt: row.latestMeetingAt ? new Date(row.latestMeetingAt) : null,
  }));
}

export async function listManagedUsers(db: DatabaseClient): Promise<AdminUserSummary[]> {
  await assertSchemaReady(db);

  const users = await db.user.findMany({
    orderBy: { createdAt: 'asc' },
    select: {
      id: true,
      email: true,
      displayName: true,
      createdAt: true,
      workspaces: {
        select: {
          id: true,
          name: true,
          createdAt: true,
          _count: {
            select: {
              meetings: true,
              collections: true,
              globalChatSessions: true,
            },
          },
        },
      },
      _count: {
        select: {
          authSessions: true,
        },
      },
    },
  });

  return users.map((user) => {
    const workspace = user.workspaces[0] ?? null;

    return {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      createdAt: user.createdAt,
      authSessionCount: user._count.authSessions,
      workspace: workspace
        ? {
            id: workspace.id,
            name: workspace.name,
            createdAt: workspace.createdAt,
            meetingCount: workspace._count.meetings,
            collectionCount: workspace._count.collections,
            globalChatSessionCount: workspace._count.globalChatSessions,
          }
        : null,
    };
  });
}

export async function listInviteCodes(db: DatabaseClient): Promise<AdminInviteCodeSummary[]> {
  await assertSchemaReady(db);

  return db.inviteCode.findMany({
    orderBy: { createdAt: 'desc' },
    include: {
      redeemedByUser: {
        select: {
          id: true,
          email: true,
        },
      },
    },
  });
}

export async function createManagedUser(
  db: PrismaClient,
  input: {
    email: string;
    password: string;
    displayName?: string | null;
    legacyWorkspaceId?: string | null;
  }
) {
  await assertSchemaReady(db);

  const email = normalizeEmail(input.email);
  const password = input.password;
  const displayName = input.displayName?.trim() || '';
  const legacyWorkspaceId = input.legacyWorkspaceId?.trim() || null;

  if (!email) {
    throw new AdminManagementError(400, '邮箱不能为空');
  }
  if (!isPasswordValid(password)) {
    throw new AdminManagementError(400, '密码至少需要 8 位');
  }

  const existingUser = await db.user.findUnique({
    where: { email },
    select: { id: true },
  });
  if (existingUser) {
    throw new AdminManagementError(409, '该邮箱已存在');
  }

  const passwordHash = await hashPassword(password);

  return db.$transaction(async (tx) => {
    const user = await tx.user.create({
      data: {
        email,
        passwordHash,
        displayName,
      },
      select: {
        id: true,
        email: true,
        displayName: true,
      },
    });

    const workspace = legacyWorkspaceId
      ? await claimLegacyWorkspaceForUser(tx, {
          userId: user.id,
          workspaceId: legacyWorkspaceId,
        })
      : await ensureDefaultWorkspaceForUser(tx, {
          userId: user.id,
        });

    return {
      user,
      workspace: {
        id: workspace.id,
        name: workspace.name,
      },
    };
  });
}

export async function assignLegacyWorkspaceToUser(
  db: DatabaseClient,
  input: {
    workspaceId: string;
    userId: string;
  }
) {
  await assertSchemaReady(db);

  const user = await db.user.findUnique({
    where: { id: input.userId },
    select: {
      id: true,
      email: true,
      displayName: true,
    },
  });

  if (!user) {
    throw new AdminManagementError(404, '未找到目标账号');
  }

  const workspace = await claimLegacyWorkspaceForUser(db, input);

  return {
    user,
    workspace: {
      id: workspace.id,
      name: workspace.name,
    },
  };
}

export async function resetManagedUserPassword(
  db: DatabaseClient,
  input: {
    userId: string;
    password: string;
  }
) {
  await assertSchemaReady(db);

  if (!isPasswordValid(input.password)) {
    throw new AdminManagementError(400, '密码至少需要 8 位');
  }

  try {
    return await db.user.update({
      where: { id: input.userId },
      data: {
        passwordHash: await hashPassword(input.password),
      },
      select: {
        id: true,
        email: true,
        displayName: true,
      },
    });
  } catch (error) {
    if (
      typeof error === 'object' &&
      error &&
      'code' in error &&
      (error as { code?: string }).code === 'P2025'
    ) {
      throw new AdminManagementError(404, '未找到需要重置密码的账号');
    }

    throw error;
  }
}

export async function createInviteCodeRecord(
  db: DatabaseClient,
  input: {
    note?: string | null;
    code?: string | null;
  }
) {
  await assertSchemaReady(db);

  const requestedCode = input.code ? normalizeInviteCode(input.code) : '';
  const code = requestedCode || generateInviteCode();

  return db.inviteCode.create({
    data: {
      code,
      note: input.note?.trim() || '',
    },
  });
}

export async function revokeInviteCodeRecord(
  db: DatabaseClient,
  input: {
    inviteCodeId: string;
  }
) {
  await assertSchemaReady(db);

  return db.inviteCode.update({
    where: { id: input.inviteCodeId },
    data: { isRevoked: true },
  });
}

export async function loadAdminDashboardData(db: DatabaseClient) {
  const schema = await getAdminSchemaStatus(db);

  if (!schema.ready) {
    return {
      schema,
      users: [] as AdminUserSummary[],
    };
  }

  const users = await listManagedUsers(db);

  return {
    schema,
    users,
  };
}
