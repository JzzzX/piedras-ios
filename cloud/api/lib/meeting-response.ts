import { buildMeetingAudioProcessingStatus } from './meeting-audio-processing.ts';
import { buildMeetingAttachmentFileURL } from './meeting-attachment.ts';

export function serializeMeetingDetail(
  meeting: {
    id: string;
    collectionId?: string | null;
    previousCollectionId?: string | null;
    deletedAt?: Date | null;
    speakers: string;
    audioUpdatedAt: Date | null;
    audioProcessingState: string;
    audioProcessingError: string;
    audioProcessingAttempts: number;
    audioProcessingRequestedAt: Date | null;
    audioProcessingStartedAt: Date | null;
    audioProcessingCompletedAt: Date | null;
    audioCloudSyncEnabled?: boolean | null;
    noteAttachments?: Array<{
      id: string;
      mimeType: string;
      originalName: string;
      extractedText: string;
      createdAt: Date;
      updatedAt: Date;
    }>;
  },
  options: { hasAudio: boolean }
) {
  const noteAttachments = (meeting.noteAttachments ?? []).map((attachment) => ({
    id: attachment.id,
    mimeType: attachment.mimeType,
    originalName: attachment.originalName,
    extractedText: attachment.extractedText,
    createdAt: attachment.createdAt,
    updatedAt: attachment.updatedAt,
    url: buildMeetingAttachmentFileURL(meeting.id, attachment.id),
  }));
  const noteAttachmentsTextContext = (meeting.noteAttachments ?? [])
    .map((attachment) => attachment.extractedText.trim())
    .filter(Boolean)
    .join('\n\n');

  return {
    ...meeting,
    speakers: JSON.parse(meeting.speakers),
    hasAudio: options.hasAudio,
    audioUrl: options.hasAudio
      ? `/api/meetings/${meeting.id}/audio?t=${meeting.audioUpdatedAt?.getTime() || Date.now()}`
      : null,
    audioCloudSyncEnabled: meeting.audioCloudSyncEnabled ?? true,
    noteAttachments,
    noteAttachmentsTextContext,
    ...buildMeetingAudioProcessingStatus(meeting),
  };
}
