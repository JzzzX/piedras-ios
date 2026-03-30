export interface ASRRecognitionUtterance {
  text: string;
  startTimeMs: number;
  endTimeMs: number;
  definite: boolean;
}

export interface ASRRecognitionSnapshot {
  revision: number;
  fullText: string;
  audioEndTimeMs: number;
  utterances: ASRRecognitionUtterance[];
}

interface BuildRecognitionSnapshotOptions {
  revision: number;
  fallbackEndTimeMs: number;
}

interface BuildAsrSessionContextInput {
  workspaceName?: string | null;
  meetingTitle?: string | null;
  recentTranscriptTexts?: string[] | null;
  noteSummary?: string | null;
  maxTranscriptEntries?: number;
}

function normalizeText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function toNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function toBoolean(value: unknown): boolean {
  return value === true || value === 1 || value === '1' || value === 'true' || value === 'final';
}

export function buildRecognitionSnapshot(
  payload: Record<string, unknown>,
  options: BuildRecognitionSnapshotOptions
): ASRRecognitionSnapshot {
  const rawResult = (payload.result ?? payload) as Record<string, unknown>;
  const rawUtterances = Array.isArray(rawResult.utterances) ? rawResult.utterances : [];
  const utterances = rawUtterances
    .map((item) => {
      const utterance = item as Record<string, unknown>;
      const text = normalizeText(utterance.text ?? utterance.utterance ?? utterance.result);
      if (!text) return null;

      const startTimeMs =
        toNumber(utterance.start_time) ??
        toNumber(utterance.startTime) ??
        toNumber(utterance.start_ms) ??
        0;
      const endTimeMs =
        toNumber(utterance.end_time) ??
        toNumber(utterance.endTime) ??
        toNumber(utterance.end_ms) ??
        options.fallbackEndTimeMs;

      return {
        text,
        startTimeMs,
        endTimeMs: Math.max(endTimeMs, startTimeMs),
        definite: toBoolean(utterance.definite ?? utterance.is_final ?? utterance.final),
      } satisfies ASRRecognitionUtterance;
    })
    .filter((utterance): utterance is ASRRecognitionUtterance => utterance !== null);

  const fullText = normalizeText(rawResult.text)
    || utterances.map((utterance) => utterance.text).join(' ').trim();
  const audioEndTimeMs = utterances[utterances.length - 1]?.endTimeMs ?? options.fallbackEndTimeMs;

  return {
    revision: options.revision,
    fullText,
    audioEndTimeMs,
    utterances,
  };
}

export function buildAsrSessionContext(input: BuildAsrSessionContextInput): string {
  const maxTranscriptEntries = Math.max(0, input.maxTranscriptEntries ?? 3);
  const recentTranscripts = (input.recentTranscriptTexts ?? [])
    .map((item) => normalizeText(item))
    .filter(Boolean)
    .reverse()
    .slice(0, maxTranscriptEntries);

  return JSON.stringify({
    workspace_name: normalizeText(input.workspaceName),
    meeting_title: normalizeText(input.meetingTitle),
    note_summary: normalizeText(input.noteSummary),
    recent_transcripts: recentTranscripts,
  });
}
