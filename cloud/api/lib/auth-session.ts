import type { Prisma, PrismaClient } from '@prisma/client';

import {
  generateSessionToken,
  hashPassword,
  hashSessionToken,
  isPasswordValid,
  normalizeEmail,
  normalizeInviteCode,
  verifyPassword,
} from './auth.ts';
import { ensureDefaultWorkspaceForUser } from './user-workspace-db.ts';

const SESSION_TTL_DAYS = 30;

type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export class AuthValidationError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export interface AuthResult {
  user: {
    id: string;
    email: string;
  };
  workspace: {
    id: string;
    name: string;
  };
  session: {
    token: string;
    refreshToken?: string | null;
    expiresAt: Date;
  };
}

function buildExpiryDate() {
  return new Date(Date.now() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
}

function sanitizeDisplayName(displayName?: string | null) {
  return displayName?.trim() || '';
}

function toAuthResult(input: {
  user: { id: string; email: string };
  workspace: { id: string; name: string };
  sessionToken: string;
  refreshToken?: string | null;
  expiresAt: Date;
}): AuthResult {
  return {
    user: input.user,
    workspace: input.workspace,
    session: {
      token: input.sessionToken,
      refreshToken: input.refreshToken ?? null,
      expiresAt: input.expiresAt,
    },
  };
}

async function createSession(
  db: DatabaseClient,
  userId: string
): Promise<{ token: string; expiresAt: Date }> {
  const token = generateSessionToken();
  const expiresAt = buildExpiryDate();

  await db.authSession.create({
    data: {
      tokenHash: hashSessionToken(token),
      userId,
      expiresAt,
    },
  });

  return { token, expiresAt };
}

export async function registerWithInviteCode(
  db: PrismaClient,
  input: {
    email: string;
    password: string;
    inviteCode: string;
    displayName?: string | null;
  }
): Promise<AuthResult> {
  const email = normalizeEmail(input.email);
  const inviteCode = normalizeInviteCode(input.inviteCode);
  const password = input.password;

  if (!email) {
    throw new AuthValidationError(400, '邮箱不能为空');
  }

  if (!isPasswordValid(password)) {
    throw new AuthValidationError(400, '密码至少需要 8 位');
  }

  if (!inviteCode) {
    throw new AuthValidationError(400, '邀请码不能为空');
  }

  const existingUser = await db.user.findUnique({
    where: { email },
    select: { id: true },
  });

  if (existingUser) {
    throw new AuthValidationError(409, '该邮箱已注册');
  }

  const passwordHash = await hashPassword(password);

  const result = await db.$transaction(async (tx: Prisma.TransactionClient) => {
    const existingInviteCode = await tx.inviteCode.findUnique({
      where: { code: inviteCode },
      select: {
        id: true,
        isRevoked: true,
        redeemedAt: true,
      },
    });

    if (!existingInviteCode || existingInviteCode.isRevoked || existingInviteCode.redeemedAt) {
      throw new AuthValidationError(400, '邀请码不可用');
    }

    const user = await tx.user.create({
      data: {
        email,
        passwordHash,
        displayName: sanitizeDisplayName(input.displayName),
      },
      select: {
        id: true,
        email: true,
      },
    });

    const workspace = await ensureDefaultWorkspaceForUser(tx, {
      userId: user.id,
    });

    const redeemed = await tx.inviteCode.updateMany({
      where: {
        id: existingInviteCode.id,
        isRevoked: false,
        redeemedAt: null,
      },
      data: {
        redeemedAt: new Date(),
        redeemedByUserId: user.id,
      },
    });

    if (redeemed.count !== 1) {
      throw new AuthValidationError(409, '邀请码已被使用');
    }

    const session = await createSession(tx, user.id);

    return toAuthResult({
      user,
      workspace: {
        id: workspace.id,
        name: workspace.name,
      },
      sessionToken: session.token,
      expiresAt: session.expiresAt,
    });
  });

  return result;
}

export async function loginWithPassword(
  db: PrismaClient,
  input: {
    email: string;
    password: string;
  }
): Promise<AuthResult> {
  const email = normalizeEmail(input.email);
  const password = input.password;

  if (!email || !password) {
    throw new AuthValidationError(400, '邮箱和密码不能为空');
  }

  const user = await db.user.findUnique({
    where: { email },
    select: {
      id: true,
      email: true,
      passwordHash: true,
    },
  });

  if (!user || !user.passwordHash || !(await verifyPassword(password, user.passwordHash))) {
    throw new AuthValidationError(401, '邮箱或密码错误');
  }

  const workspace = await ensureDefaultWorkspaceForUser(db, {
    userId: user.id,
  });
  const session = await createSession(db, user.id);

  return toAuthResult({
    user: {
      id: user.id,
      email: user.email,
    },
    workspace: {
      id: workspace.id,
      name: workspace.name,
    },
    sessionToken: session.token,
    expiresAt: session.expiresAt,
  });
}
