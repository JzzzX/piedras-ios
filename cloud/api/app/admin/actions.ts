'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

import {
  clearAdminSessionCookie,
  isAdminSecretMatch,
  readAdminSessionState,
  setAdminSessionCookie,
} from '@/lib/admin-auth';
import {
  AdminManagementError,
  assignLegacyWorkspaceToUser,
  createInviteCodeRecord,
  createManagedUser,
  resetManagedUserPassword,
  revokeInviteCodeRecord,
} from '@/lib/admin-management';
import { prisma } from '@/lib/db';

function firstValue(formData: FormData, key: string) {
  return String(formData.get(key) ?? '').trim();
}

function redirectWithStatus(kind: 'error' | 'message', message: string): never {
  const params = new URLSearchParams({
    [kind]: message,
  });
  redirect(`/?${params.toString()}#account-admin`);
}

async function requireAdminSession() {
  const session = await readAdminSessionState();

  if (!session.configured) {
    redirectWithStatus('error', 'ADMIN_API_SECRET 未配置，暂时无法使用管理后台');
  }

  if (!session.authenticated) {
    redirectWithStatus('error', '请先登录管理后台');
  }
}

function handleActionError(error: unknown): never {
  if (error instanceof AdminManagementError) {
    redirectWithStatus('error', error.message);
  }

  if (error instanceof Error) {
    redirectWithStatus('error', error.message);
  }

  redirectWithStatus('error', '管理操作失败，请稍后重试');
}

export async function adminLoginAction(formData: FormData) {
  const configuredSecret = process.env.ADMIN_API_SECRET?.trim();
  if (!configuredSecret) {
    redirectWithStatus('error', 'ADMIN_API_SECRET 未配置，先补环境变量');
  }

  const providedSecret = firstValue(formData, 'secret');
  if (!isAdminSecretMatch(configuredSecret, providedSecret)) {
    redirectWithStatus('error', '管理员密钥错误');
  }

  await setAdminSessionCookie(configuredSecret);
  redirectWithStatus('message', '已进入管理后台');
}

export async function adminLogoutAction() {
  await clearAdminSessionCookie();
  redirectWithStatus('message', '已退出管理后台');
}

export async function createManagedUserAction(formData: FormData) {
  await requireAdminSession();

  let result: Awaited<ReturnType<typeof createManagedUser>>;
  try {
    result = await createManagedUser(prisma, {
      email: firstValue(formData, 'email'),
      password: firstValue(formData, 'password'),
      displayName: firstValue(formData, 'displayName') || null,
      legacyWorkspaceId: firstValue(formData, 'legacyWorkspaceId') || null,
    });
  } catch (error) {
    handleActionError(error);
  }

  revalidatePath('/');
  redirectWithStatus(
    'message',
    `已创建账号 ${result.user.email}，当前工作区：${result.workspace.name}`
  );
}

export async function assignLegacyWorkspaceAction(formData: FormData) {
  await requireAdminSession();

  let result: Awaited<ReturnType<typeof assignLegacyWorkspaceToUser>>;
  try {
    result = await assignLegacyWorkspaceToUser(prisma, {
      workspaceId: firstValue(formData, 'workspaceId'),
      userId: firstValue(formData, 'userId'),
    });
  } catch (error) {
    handleActionError(error);
  }

  revalidatePath('/');
  redirectWithStatus(
    'message',
    `已把 legacy 工作区 ${result.workspace.name} 交给 ${result.user.email}`
  );
}

export async function resetManagedUserPasswordAction(formData: FormData) {
  await requireAdminSession();

  let result: Awaited<ReturnType<typeof resetManagedUserPassword>>;
  try {
    result = await resetManagedUserPassword(prisma, {
      userId: firstValue(formData, 'userId'),
      password: firstValue(formData, 'password'),
    });
  } catch (error) {
    handleActionError(error);
  }

  revalidatePath('/');
  redirectWithStatus('message', `已重置 ${result.email} 的密码`);
}

export async function createInviteCodeAction(formData: FormData) {
  await requireAdminSession();

  let inviteCode: Awaited<ReturnType<typeof createInviteCodeRecord>>;
  try {
    inviteCode = await createInviteCodeRecord(prisma, {
      note: firstValue(formData, 'note') || null,
      code: firstValue(formData, 'code') || null,
    });
  } catch (error) {
    handleActionError(error);
  }

  revalidatePath('/');
  redirectWithStatus('message', `已生成邀请码 ${inviteCode.code}`);
}

export async function revokeInviteCodeAction(formData: FormData) {
  await requireAdminSession();

  let inviteCode: Awaited<ReturnType<typeof revokeInviteCodeRecord>>;
  try {
    inviteCode = await revokeInviteCodeRecord(prisma, {
      inviteCodeId: firstValue(formData, 'inviteCodeId'),
    });
  } catch (error) {
    handleActionError(error);
  }

  revalidatePath('/');
  redirectWithStatus('message', `已停用邀请码 ${inviteCode.code}`);
}
