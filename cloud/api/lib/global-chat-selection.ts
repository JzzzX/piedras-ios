import type { GlobalKnowledgeSource, GlobalRetrievalResult } from './global-chat';

export interface ClientRetrievalSource {
  ref: string;
  type: 'meeting' | 'asset';
  title: string;
  date: string;
}

interface SelectRetrievalInput {
  localRetrievalContext?: string;
  localRetrievalSources?: ClientRetrievalSource[];
  fallback: GlobalRetrievalResult;
}

export function selectRetrievalResult({
  localRetrievalContext,
  localRetrievalSources,
  fallback,
}: SelectRetrievalInput): {
  context: string;
  sources: Array<Pick<GlobalKnowledgeSource, 'ref' | 'type' | 'title' | 'date'>>;
} {
  const normalizedContext = localRetrievalContext?.trim();
  const normalizedSources = (localRetrievalSources || []).filter(
    (source) => source.ref && source.type && source.title && source.date
  );

  if (normalizedContext && normalizedSources.length > 0) {
    return {
      context: normalizedContext,
      sources: normalizedSources.map((source) => ({
        ref: source.ref,
        type: source.type,
        title: source.title,
        date: source.date,
      })),
    };
  }

  return {
    context: fallback.context,
    sources: fallback.sources.map((source) => ({
      ref: source.ref,
      type: source.type,
      title: source.title,
      date: source.date,
    })),
  };
}
