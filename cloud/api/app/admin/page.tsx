import { redirect } from 'next/navigation';

export const dynamic = 'force-dynamic';

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const redirectParams = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (Array.isArray(value)) {
      if (value[0]) {
        redirectParams.set(key, value[0]);
      }
    } else if (value) {
      redirectParams.set(key, value);
    }
  }
  const target = redirectParams.toString();
  redirect(target ? `/?${target}#account-admin` : '/#account-admin');
}
