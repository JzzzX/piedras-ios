const crypto = require('node:crypto');
const { promisify } = require('node:util');
const { execFile } = require('node:child_process');
const path = require('node:path');
const { PrismaClient } = require('@prisma/client');

const scrypt = promisify(crypto.scrypt);
const execFileAsync = promisify(execFile);

const LEGACY_BOOTSTRAP_USERS = [
  {
    email: 'legacy-main@piedras.local',
    displayName: '历史主数据',
  },
  {
    email: 'legacy-archive@piedras.local',
    displayName: '历史归档数据',
  },
];

const MEDIA_SYNC_BOOTSTRAP_SQL = `
ALTER TABLE "Meeting"
  ADD COLUMN IF NOT EXISTS "audioCloudSyncEnabled" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "Meeting"
  ADD COLUMN IF NOT EXISTS "previousCollectionId" TEXT;

ALTER TABLE "Meeting"
  ADD COLUMN IF NOT EXISTS "deletedAt" TIMESTAMP(3);

CREATE TABLE IF NOT EXISTS "MeetingAttachment" (
  "id" TEXT NOT NULL,
  "originalName" TEXT NOT NULL,
  "mimeType" TEXT NOT NULL,
  "fileSize" INTEGER NOT NULL DEFAULT 0,
  "extractedText" TEXT NOT NULL DEFAULT '',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "meetingId" TEXT NOT NULL,

  CONSTRAINT "MeetingAttachment_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "MeetingAttachment_meetingId_updatedAt_idx"
  ON "MeetingAttachment"("meetingId", "updatedAt");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'MeetingAttachment_meetingId_fkey'
  ) THEN
    ALTER TABLE "MeetingAttachment"
      ADD CONSTRAINT "MeetingAttachment_meetingId_fkey"
      FOREIGN KEY ("meetingId") REFERENCES "Meeting"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
`;

function summarizeAuthSchemaStatus(input) {
  const tableNames = new Set(input.tableNames);
  const status = {
    ready: true,
    missingItems: [],
    userTable: tableNames.has('User'),
    authSessionTable: tableNames.has('AuthSession'),
    inviteCodeTable: tableNames.has('InviteCode'),
    workspaceOwnerColumnPresent: Boolean(input.workspaceOwnerColumnPresent),
    userAuthUserIdColumnPresent: Boolean(input.userAuthUserIdColumnPresent),
    userAuthUserIdUniqueIndexPresent: Boolean(input.userAuthUserIdUniqueIndexPresent),
    userPasswordHashNullable: Boolean(input.userPasswordHashNullable),
    meetingAudioEnhancedColumnsPresent: input.meetingAudioEnhancedColumnsPresent !== false,
  };

  if (!status.userTable) {
    status.ready = false;
    status.missingItems.push('User 表');
  }
  if (!status.authSessionTable) {
    status.ready = false;
    status.missingItems.push('AuthSession 表');
  }
  if (!status.inviteCodeTable) {
    status.ready = false;
    status.missingItems.push('InviteCode 表');
  }
  if (!status.workspaceOwnerColumnPresent) {
    status.ready = false;
    status.missingItems.push('Workspace.ownerUserId 字段');
  }
  if (!status.userAuthUserIdColumnPresent) {
    status.ready = false;
    status.missingItems.push('User.authUserId 字段');
  }
  if (!status.userAuthUserIdUniqueIndexPresent) {
    status.ready = false;
    status.missingItems.push('User.authUserId 唯一索引');
  }
  if (!status.userPasswordHashNullable) {
    status.ready = false;
    status.missingItems.push('User.passwordHash 可空约束');
  }
  if (!status.meetingAudioEnhancedColumnsPresent) {
    status.ready = false;
    status.missingItems.push('Meeting 音频 AI 笔记字段');
  }

  return status;
}

function summarizeMediaSyncSchemaStatus(input) {
  const status = {
    ready: true,
    missingItems: [],
    meetingAudioCloudSyncEnabledColumnPresent: Boolean(input.meetingAudioCloudSyncEnabledColumnPresent),
    meetingPreviousCollectionIdColumnPresent: Boolean(input.meetingPreviousCollectionIdColumnPresent),
    meetingDeletedAtColumnPresent: Boolean(input.meetingDeletedAtColumnPresent),
    meetingAttachmentTablePresent: Boolean(input.meetingAttachmentTablePresent),
    meetingAttachmentIndexPresent: Boolean(input.meetingAttachmentIndexPresent),
    meetingAttachmentForeignKeyPresent: Boolean(input.meetingAttachmentForeignKeyPresent),
  };

  if (!status.meetingAudioCloudSyncEnabledColumnPresent) {
    status.ready = false;
    status.missingItems.push('Meeting.audioCloudSyncEnabled 字段');
  }
  if (!status.meetingPreviousCollectionIdColumnPresent) {
    status.ready = false;
    status.missingItems.push('Meeting.previousCollectionId 字段');
  }
  if (!status.meetingDeletedAtColumnPresent) {
    status.ready = false;
    status.missingItems.push('Meeting.deletedAt 字段');
  }
  if (!status.meetingAttachmentTablePresent) {
    status.ready = false;
    status.missingItems.push('MeetingAttachment 表');
  }
  if (!status.meetingAttachmentIndexPresent) {
    status.ready = false;
    status.missingItems.push('MeetingAttachment_meetingId_updatedAt_idx 索引');
  }
  if (!status.meetingAttachmentForeignKeyPresent) {
    status.ready = false;
    status.missingItems.push('MeetingAttachment_meetingId_fkey 外键');
  }

  return status;
}

function mergeSchemaStatuses(...statuses) {
  const missingItems = [];

  for (const status of statuses) {
    if (!status) continue;
    if (Array.isArray(status.missingItems)) {
      for (const item of status.missingItems) {
        if (!missingItems.includes(item)) {
          missingItems.push(item);
        }
      }
    }
  }

  return {
    ready: statuses.every((status) => status?.ready !== false),
    missingItems,
  };
}

function buildLegacyBootstrapPlans(workspaces) {
  return [...workspaces]
    .sort((left, right) => {
      if (right.meetingCount !== left.meetingCount) {
        return right.meetingCount - left.meetingCount;
      }
      return String(left.name).localeCompare(String(right.name), 'zh-CN');
    })
    .slice(0, LEGACY_BOOTSTRAP_USERS.length)
    .map((workspace, index) => ({
      email: LEGACY_BOOTSTRAP_USERS[index].email,
      displayName: LEGACY_BOOTSTRAP_USERS[index].displayName,
      workspaceId: workspace.id,
      workspaceName: workspace.name,
    }));
}

async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const derivedKey = await scrypt(password, salt, 64);
  return `scrypt$${salt.toString('base64url')}$${Buffer.from(derivedKey).toString('base64url')}`;
}

async function getAuthSchemaStatus(prisma) {
  const tables = await prisma.$queryRawUnsafe(`
    SELECT table_name AS "objectName"
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('User', 'AuthSession', 'InviteCode')
  `);
  const workspaceOwnerColumn = await prisma.$queryRawUnsafe(`
    SELECT column_name AS "objectName"
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Workspace'
      AND column_name = 'ownerUserId'
  `);
  const userAuthColumns = await prisma.$queryRawUnsafe(`
    SELECT
      column_name AS "columnName",
      is_nullable AS "isNullable"
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'User'
      AND column_name IN ('authUserId', 'passwordHash')
  `);
  const userAuthIndexes = await prisma.$queryRawUnsafe(`
    SELECT indexname AS "indexName"
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'User'
      AND indexname = 'User_authUserId_key'
  `);
  const meetingAudioEnhancedColumns = await prisma.$queryRawUnsafe(`
    SELECT column_name AS "columnName"
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Meeting'
      AND column_name IN (
        'audioEnhancedNotes',
        'audioEnhancedNotesStatus',
        'audioEnhancedNotesError',
        'audioEnhancedNotesUpdatedAt',
        'audioEnhancedNotesProvider',
        'audioEnhancedNotesModel'
      )
  `);
  const userAuthUserIdColumn = userAuthColumns.find((item) => item.columnName === 'authUserId');
  const userPasswordHashColumn = userAuthColumns.find((item) => item.columnName === 'passwordHash');

  return summarizeAuthSchemaStatus({
    tableNames: tables.map((item) => item.objectName),
    workspaceOwnerColumnPresent: workspaceOwnerColumn.length > 0,
    userAuthUserIdColumnPresent: Boolean(userAuthUserIdColumn),
    userAuthUserIdUniqueIndexPresent: userAuthIndexes.length > 0,
    userPasswordHashNullable: userPasswordHashColumn?.isNullable === 'YES',
    meetingAudioEnhancedColumnsPresent: meetingAudioEnhancedColumns.length === 6,
  });
}

async function getMediaSyncSchemaStatus(prisma) {
  const meetingColumns = await prisma.$queryRawUnsafe(`
    SELECT column_name AS "objectName"
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'Meeting'
      AND column_name IN ('audioCloudSyncEnabled', 'previousCollectionId', 'deletedAt')
  `);
  const meetingAttachmentTable = await prisma.$queryRawUnsafe(`
    SELECT table_name AS "objectName"
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'MeetingAttachment'
  `);
  const meetingAttachmentIndex = await prisma.$queryRawUnsafe(`
    SELECT indexname AS "objectName"
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'MeetingAttachment'
      AND indexname = 'MeetingAttachment_meetingId_updatedAt_idx'
  `);
  const meetingAttachmentForeignKey = await prisma.$queryRawUnsafe(`
    SELECT conname AS "objectName"
    FROM pg_constraint
    WHERE conname = 'MeetingAttachment_meetingId_fkey'
  `);

  return summarizeMediaSyncSchemaStatus({
    meetingAudioCloudSyncEnabledColumnPresent: meetingColumns.some(
      (item) => item.objectName === 'audioCloudSyncEnabled'
    ),
    meetingPreviousCollectionIdColumnPresent: meetingColumns.some(
      (item) => item.objectName === 'previousCollectionId'
    ),
    meetingDeletedAtColumnPresent: meetingColumns.some((item) => item.objectName === 'deletedAt'),
    meetingAttachmentTablePresent: meetingAttachmentTable.length > 0,
    meetingAttachmentIndexPresent: meetingAttachmentIndex.length > 0,
    meetingAttachmentForeignKeyPresent: meetingAttachmentForeignKey.length > 0,
  });
}

async function runPrismaDbPush(logger) {
  logger('auth_schema_bootstrap_running', {
    cwd: path.resolve(__dirname, '..'),
  });

  const result = await execFileAsync(
    process.platform === 'win32' ? 'npx.cmd' : 'npx',
    ['prisma', 'db', 'push', '--accept-data-loss'],
    {
      cwd: path.resolve(__dirname, '..'),
      env: process.env,
    }
  );

  logger('auth_schema_bootstrap_completed', {
    stdout: result.stdout.trim(),
    stderr: result.stderr.trim(),
  });
}

async function runMediaSyncSchemaBootstrap(prisma, logger) {
  logger('media_sync_schema_bootstrap_running', {});
  await prisma.$executeRawUnsafe(MEDIA_SYNC_BOOTSTRAP_SQL);
  logger('media_sync_schema_bootstrap_completed', {});
}

async function listLegacyWorkspaces(prisma) {
  const rows = await prisma.$queryRawUnsafe(`
    SELECT
      w.id,
      w.name,
      COUNT(DISTINCT m.id)::int AS "meetingCount"
    FROM "Workspace" w
    LEFT JOIN "Meeting" m ON m."workspaceId" = w.id
    WHERE w."ownerUserId" IS NULL
    GROUP BY w.id, w.name
    ORDER BY "meetingCount" DESC, w."createdAt" ASC
  `);

  return rows.map((row) => ({
    id: row.id,
    name: row.name,
    meetingCount: Number(row.meetingCount ?? 0),
  }));
}

async function ensureLegacyBootstrapUsers(prisma, logger) {
  const bootstrapPassword = String(process.env.LEGACY_BOOTSTRAP_PASSWORD || '').trim();
  if (!bootstrapPassword) {
    logger('legacy_account_bootstrap_skipped', {
      reason: 'LEGACY_BOOTSTRAP_PASSWORD missing',
    });
    return [];
  }

  const workspaces = await listLegacyWorkspaces(prisma);
  const plans = buildLegacyBootstrapPlans(workspaces);
  const createdUsers = [];

  for (const plan of plans) {
    const existingUser = await prisma.user.findUnique({
      where: { email: plan.email },
      select: {
        id: true,
        email: true,
      },
    });

    if (existingUser) {
      createdUsers.push({
        email: existingUser.email,
        created: false,
        workspaceId: plan.workspaceId,
      });
      continue;
    }

    const passwordHash = await hashPassword(bootstrapPassword);
    const user = await prisma.user.create({
      data: {
        email: plan.email,
        displayName: plan.displayName,
        passwordHash,
      },
      select: {
        id: true,
        email: true,
      },
    });

    await prisma.workspace.update({
      where: { id: plan.workspaceId },
      data: { ownerUserId: user.id },
    });

    createdUsers.push({
      email: user.email,
      created: true,
      workspaceId: plan.workspaceId,
    });
  }

  logger('legacy_account_bootstrap_completed', {
    accounts: createdUsers,
  });

  return createdUsers;
}

async function bootstrapAuthRuntime(logger = () => {}) {
  const prisma = new PrismaClient();

  try {
    let authSchemaStatus = await getAuthSchemaStatus(prisma);

    if (!authSchemaStatus.ready) {
      logger('auth_schema_bootstrap_needed', {
        missingItems: authSchemaStatus.missingItems,
      });
      await prisma.$disconnect();
      await runPrismaDbPush(logger);
      await prisma.$connect();
      authSchemaStatus = await getAuthSchemaStatus(prisma);
    }

    let mediaSyncSchemaStatus = await getMediaSyncSchemaStatus(prisma);

    if (!mediaSyncSchemaStatus.ready) {
      logger('media_sync_schema_bootstrap_needed', {
        missingItems: mediaSyncSchemaStatus.missingItems,
      });
      await runMediaSyncSchemaBootstrap(prisma, logger);
      mediaSyncSchemaStatus = await getMediaSyncSchemaStatus(prisma);
    }

    const schemaStatus = mergeSchemaStatuses(authSchemaStatus, mediaSyncSchemaStatus);
    const legacyUsers = authSchemaStatus.ready
      ? await ensureLegacyBootstrapUsers(prisma, logger)
      : [];

    return {
      schemaStatus,
      legacyUsers,
    };
  } finally {
    await prisma.$disconnect().catch(() => {});
  }
}

module.exports = {
  bootstrapAuthRuntime,
  buildLegacyBootstrapPlans,
  mergeSchemaStatuses,
  summarizeAuthSchemaStatus,
  summarizeMediaSyncSchemaStatus,
};
