function normalizeText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function toNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function toBoolean(value) {
  return value === true || value === 1 || value === '1' || value === 'true' || value === 'final';
}

function buildRecognitionSnapshot(payload, options) {
  const rawResult = payload.result ?? payload;
  const rawUtterances = Array.isArray(rawResult.utterances) ? rawResult.utterances : [];
  const utterances = rawUtterances
    .map((item) => {
      const text = normalizeText(item.text ?? item.utterance ?? item.result);
      if (!text) return null;

      const startTimeMs =
        toNumber(item.start_time) ??
        toNumber(item.startTime) ??
        toNumber(item.start_ms) ??
        0;
      const endTimeMs =
        toNumber(item.end_time) ??
        toNumber(item.endTime) ??
        toNumber(item.end_ms) ??
        options.fallbackEndTimeMs;

      return {
        text,
        startTimeMs,
        endTimeMs: Math.max(endTimeMs, startTimeMs),
        definite: toBoolean(item.definite ?? item.is_final ?? item.final),
      };
    })
    .filter(Boolean);

  const fullText =
    normalizeText(rawResult.text) || utterances.map((utterance) => utterance.text).join(' ').trim();
  const audioEndTimeMs = utterances[utterances.length - 1]?.endTimeMs ?? options.fallbackEndTimeMs;

  return {
    revision: options.revision,
    fullText,
    audioEndTimeMs,
    utterances,
  };
}

module.exports = {
  buildRecognitionSnapshot,
};
