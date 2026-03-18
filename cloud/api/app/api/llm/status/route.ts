import { NextResponse } from 'next/server';
import { getLlmRuntimeStatus } from '@/lib/llm-health';

export async function GET() {
  return NextResponse.json(await getLlmRuntimeStatus());
}
