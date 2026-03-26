interface MeetingMaterialContextInput {
  transcript?: string;
  userNotes?: string;
  enhancedNotes?: string;
  noteAttachmentsContext?: string;
  segmentCommentsContext?: string;
}

interface GlobalChatContextInput {
  retrievalContext: string;
  localCommentContext?: string;
}

export function buildMeetingMaterialContext({
  transcript,
  userNotes,
  enhancedNotes,
  noteAttachmentsContext,
  segmentCommentsContext,
}: MeetingMaterialContextInput): string {
  const sections = [
    `--- 会议转写记录 ---\n${transcript || '（无）'}`,
    `--- 用户笔记要点 ---\n${userNotes || '（无）'}`,
  ];

  if (enhancedNotes !== undefined) {
    sections.push(`--- AI 会议纪要 ---\n${enhancedNotes || '（无）'}`);
  }

  sections.push(normalizeContextSection(noteAttachmentsContext, '--- 主笔记附件资料 ---'));
  sections.push(normalizeCommentContext(segmentCommentsContext));

  return sections.join('\n\n');
}

export function buildGlobalChatContextMessage({
  retrievalContext,
  localCommentContext,
}: GlobalChatContextInput): string {
  const normalizedLocalContext = localCommentContext?.trim();
  if (!normalizedLocalContext) {
    return retrievalContext;
  }

  return `${retrievalContext}\n\n${normalizedLocalContext}`;
}

function normalizeCommentContext(segmentCommentsContext?: string): string {
  return normalizeContextSection(segmentCommentsContext, '--- 转写片段评论 ---');
}

function normalizeContextSection(content: string | undefined, header: string): string {
  const trimmed = content?.trim();
  if (!trimmed) {
    return `${header}\n（无）`;
  }

  if (trimmed.startsWith('--- ')) {
    return trimmed;
  }

  return `${header}\n${trimmed}`;
}
