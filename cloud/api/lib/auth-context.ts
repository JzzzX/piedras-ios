type WorkspaceEnsurer = (input: { userId: string }) => Promise<{
  id: string;
  name: string;
}>;

interface UserRecord {
  id: string;
  email: string;
  authUserId?: string | null;
  displayName?: string | null;
}

interface UserStore {
  findUnique(args: { where: { authUserId: string } }): Promise<UserRecord | null>;
  findFirst(args: { where: { email: string } }): Promise<UserRecord | null>;
  update(args: {
    where: { id: string };
    data: { authUserId: string };
  }): Promise<UserRecord>;
  create(args: {
    data: {
      email: string;
      authUserId: string;
      displayName: string;
    };
  }): Promise<UserRecord>;
}

export interface SupabaseIdentity {
  authUserId: string;
  email: string;
  displayName?: string | null;
  sessionId: string;
  expiresAt: Date;
}

export interface ResolvedSupabaseUserContext {
  user: {
    id: string;
    email: string;
  };
  session: {
    id: string;
    expiresAt: Date;
  };
  workspace: {
    id: string;
    name: string;
  };
}

export async function resolveSupabaseUserContext(
  db: { user: UserStore },
  identity: SupabaseIdentity,
  ensureWorkspaceForUser: WorkspaceEnsurer
): Promise<ResolvedSupabaseUserContext> {
  const normalizedEmail = normalizeEmail(identity.email);
  const normalizedDisplayName = normalizeDisplayName(identity.displayName);

  let user = await db.user.findUnique({
    where: { authUserId: identity.authUserId },
  });

  if (!user) {
    const legacyUser = await db.user.findFirst({
      where: { email: normalizedEmail },
    });

    if (legacyUser) {
      user = await db.user.update({
        where: { id: legacyUser.id },
        data: { authUserId: identity.authUserId },
      });
    } else {
      user = await db.user.create({
        data: {
          email: normalizedEmail,
          authUserId: identity.authUserId,
          displayName: normalizedDisplayName,
        },
      });
    }
  }

  const workspace = await ensureWorkspaceForUser({ userId: user.id });

  return {
    user: {
      id: user.id,
      email: user.email,
    },
    session: {
      id: identity.sessionId,
      expiresAt: identity.expiresAt,
    },
    workspace: {
      id: workspace.id,
      name: workspace.name,
    },
  };
}

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

function normalizeDisplayName(displayName?: string | null) {
  return displayName?.trim() || '';
}
