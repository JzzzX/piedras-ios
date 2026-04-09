import {
  buildStartupBootstrapSnapshot,
  type StartupBootstrapSnapshot,
} from './startup-bootstrap-state.ts';

interface BackendHealthPayloadInput {
  mode: 'basic' | 'full';
  database: boolean;
  checkedAt: string;
  startupBootstrap?: Partial<StartupBootstrapSnapshot>;
  llmProviders?: string[];
  asr?: unknown;
  audioFinalization?: { ready?: boolean } | null;
  noteAttachments?: { ready?: boolean } | null;
  llm?: unknown;
}

export function buildBackendHealthPayload(input: BackendHealthPayloadInput) {
  const startupBootstrap = buildStartupBootstrapSnapshot(input.startupBootstrap);

  if (input.mode === 'basic') {
    return {
      ok: input.database && startupBootstrap.ready,
      database: input.database,
      startupBootstrap,
      checkedAt: input.checkedAt,
    };
  }

  const asrReady = Boolean(
    input.asr && typeof input.asr === 'object' && 'ready' in input.asr
      ? (input.asr as { ready?: boolean }).ready
      : false
  );
  const audioReady = Boolean(input.audioFinalization?.ready);
  const noteAttachmentsReady = Boolean(input.noteAttachments?.ready);
  const recordingReady = input.database && asrReady && audioReady && noteAttachmentsReady && startupBootstrap.ready;

  return {
    ok: recordingReady,
    database: input.database,
    llmProviders: input.llmProviders ?? [],
    asr: input.asr,
    audioFinalization: input.audioFinalization,
    noteAttachments: input.noteAttachments,
    recordingReady,
    llm: input.llm,
    startupBootstrap,
    checkedAt: input.checkedAt,
  };
}
