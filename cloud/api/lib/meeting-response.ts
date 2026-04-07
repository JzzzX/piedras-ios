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
  const {
    speakers,
    noteAttachments: rawNoteAttachments,
    audioEnhancedNotes: _audioEnhancedNotes,
    audioEnhancedNotesStatus: _audioEnhancedNotesStatus,
    audioEnhancedNotesError: _audioEnhancedNotesError,
    audioEnhancedNotesUpdatedAt: _audioEnhancedNotesUpdatedAt,
    audioEnhancedNotesProvider: _audioEnhancedNotesProvider,
    audioEnhancedNotesModel: _audioEnhancedNotesModel,
    ...meetingPayload
  } = meeting as typeof meeting & {
    audioEnhancedNotes?: string;
    audioEnhancedNotesStatus?: string;
    audioEnhancedNotesError?: string;
    audioEnhancedNotesUpdatedAt?: Date | null;
    audioEnhancedNotesProvider?: string | null;
    audioEnhancedNotesModel?: string | null;
  };

  const noteAttachments = (rawNoteAttachments ?? []).map((attachment) => ({
    id: attachment.id,
    mimeType: attachment.mimeType,
    originalName: attachment.originalName,
    extractedText: attachment.extractedText,
    createdAt: attachment.createdAt,
    updatedAt: attachment.updatedAt,
    url: buildMeetingAttachmentFileURL(meetingPayload.id, attachment.id),
  }));
  const noteAttachmentsTextContext = (rawNoteAttachments ?? [])
    .map((attachment) => attachment.extractedText.trim())
    .filter(Boolean)
    .join('\n\n');

  return {
    ...meetingPayload,
    speakers: JSON.parse(speakers),
    hasAudio: options.hasAudio,
    audioUrl: options.hasAudio
      ? `/api/meetings/${meetingPayload.id}/audio?t=${meetingPayload.audioUpdatedAt?.getTime() || Date.now()}`
      : null,
    audioCloudSyncEnabled: meetingPayload.audioCloudSyncEnabled ?? true,
    noteAttachments,
    noteAttachmentsTextContext,
    ...buildMeetingAudioProcessingStatus(meetingPayload),
  };
}
