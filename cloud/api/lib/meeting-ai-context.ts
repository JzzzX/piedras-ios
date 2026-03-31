interface MeetingMaterialContextInput {
  transcript?: string;
  userNotes?: string;
  enhancedNotes?: string;
  noteAttachmentsContext?: string;
  segmentCommentsContext?: string;
}

interface MeetingMaterialContextLimits {
  transcriptMaxChars?: number;
  userNotesMaxChars?: number;
  enhancedNotesMaxChars?: number;
  noteAttachmentsMaxChars?: number;
  segmentCommentsMaxChars?: number;
}

interface GlobalChatContextInput {
  retrievalContext: string;
  localCommentContext?: string;
}

interface AudioMeetingMaterialContextInput {
  userNotes?: string;
  noteAttachmentsContext?: string;
  segmentCommentsContext?: string;
}

export function buildMeetingMaterialContext({
  transcript,
  userNotes,
  enhancedNotes,
  noteAttachmentsContext,
  segmentCommentsContext,
}: MeetingMaterialContextInput, limits: MeetingMaterialContextLimits = {}): string {
  const sections = [
    `--- 会议转写记录 ---\n${truncateContextSection(transcript, limits.transcriptMaxChars)}`,
    `--- 用户笔记要点 ---\n${truncateContextSection(userNotes, limits.userNotesMaxChars)}`,
  ];

  if (enhancedNotes !== undefined) {
    sections.push(
      `--- AI 会议纪要 ---\n${truncateContextSection(enhancedNotes, limits.enhancedNotesMaxChars)}`
    );
  }

  sections.push(
    normalizeContextSection(
      truncateContextSection(noteAttachmentsContext, limits.noteAttachmentsMaxChars),
      '--- 主笔记附件资料 ---'
    )
  );
  sections.push(
    normalizeCommentContext(
      truncateContextSection(segmentCommentsContext, limits.segmentCommentsMaxChars)
    )
  );

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

export function buildAudioMeetingMaterialContext({
  userNotes,
  noteAttachmentsContext,
  segmentCommentsContext,
}: AudioMeetingMaterialContextInput): string {
  return [
    `--- 用户笔记要点 ---\n${truncateContextSection(userNotes)}`,
    normalizeContextSection(noteAttachmentsContext, '--- 主笔记附件资料 ---'),
    normalizeCommentContext(segmentCommentsContext),
  ].join('\n\n');
}

function normalizeCommentContext(segmentCommentsContext?: string): string {
  return normalizeContextSection(segmentCommentsContext, '--- 转写片段评论 ---');
}

function truncateContextSection(content: string | undefined, maxChars?: number): string {
  const trimmed = content?.trim();
  if (!trimmed) {
    return '（无）';
  }

  if (!maxChars || trimmed.length <= maxChars) {
    return trimmed;
  }

  return `${trimmed.slice(0, maxChars)}（以下内容已截断）`;
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
