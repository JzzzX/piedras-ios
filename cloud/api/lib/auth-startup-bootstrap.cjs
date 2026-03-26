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

function summarizeAuthSchemaStatus(input) {
  const tableNames = new Set(input.tableNames);
  const status = {
    ready: true,
    missingItems: [],
    userTable: tableNames.has('User'),
    authSessionTable: tableNames.has('AuthSession'),
    inviteCodeTable: tableNames.has('InviteCode'),
    workspaceOwnerColumnPresent: Boolean(input.workspaceOwnerColumnPresent),
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

  return status;
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

  return summarizeAuthSchemaStatus({
    tableNames: tables.map((item) => item.objectName),
    workspaceOwnerColumnPresent: workspaceOwnerColumn.length > 0,
  });
}

async function runPrismaDbPush(logger) {
  logger('auth_schema_bootstrap_running', {
    cwd: path.resolve(__dirname, '..'),
  });

  const result = await execFileAsync(
    process.platform === 'win32' ? 'npx.cmd' : 'npx',
    ['prisma', 'db', 'push', '--skip-generate', '--accept-data-loss'],
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
    let schemaStatus = await getAuthSchemaStatus(prisma);

    if (!schemaStatus.ready) {
      logger('auth_schema_bootstrap_needed', {
        missingItems: schemaStatus.missingItems,
      });
      await prisma.$disconnect();
      await runPrismaDbPush(logger);
      await prisma.$connect();
      schemaStatus = await getAuthSchemaStatus(prisma);
    }

    const legacyUsers = schemaStatus.ready
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
  summarizeAuthSchemaStatus,
};
