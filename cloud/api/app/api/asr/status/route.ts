import { NextResponse } from 'next/server';
import { getAsrRuntimeStatus } from '@/lib/asr';

export async function GET() {
  return NextResponse.json(await getAsrRuntimeStatus());
}
