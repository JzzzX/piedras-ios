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
  resetManagedUserPassword,
} from '@/lib/admin-management';
import { prisma } from '@/lib/db';

function firstValue(formData: FormData, key: string) {
  return String(formData.get(key) ?? '').trim();
}

function redirectWithStatus(kind: 'error' | 'message', message: string): never {
  const params = new URLSearchParams({
    [kind]: message,
  });
  redirect(`/admin?${params.toString()}`);
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

  revalidatePath('/admin');
  redirectWithStatus('message', `已重置 ${result.email} 的密码`);
}
