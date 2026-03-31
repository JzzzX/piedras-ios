import { buildMeetingAudioProcessingStatus } from './meeting-audio-processing.ts';

export function serializeMeetingDetail(
  meeting: {
    id: string;
    speakers: string;
    audioUpdatedAt: Date | null;
    audioProcessingState: string;
    audioProcessingError: string;
    audioProcessingAttempts: number;
    audioProcessingRequestedAt: Date | null;
    audioProcessingStartedAt: Date | null;
    audioProcessingCompletedAt: Date | null;
  },
  options: { hasAudio: boolean }
) {
  return {
    ...meeting,
    speakers: JSON.parse(meeting.speakers),
    hasAudio: options.hasAudio,
    audioUrl: options.hasAudio
      ? `/api/meetings/${meeting.id}/audio?t=${meeting.audioUpdatedAt?.getTime() || Date.now()}`
      : null,
    ...buildMeetingAudioProcessingStatus(meeting),
  };
}
