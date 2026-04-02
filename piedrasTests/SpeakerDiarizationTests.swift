import Foundation
import Testing
@testable import piedras

struct SpeakerDiarizationTests {
    @Test
    func decodesRemoteMeetingDetailWithSpeakerMap() throws {
        let payload = """
        {
          "id": "meeting-speakers",
          "title": "Interview",
          "date": "2026-03-19T09:15:00.000Z",
          "status": "ended",
          "duration": 95,
          "audioMimeType": null,
          "audioDuration": null,
          "audioUpdatedAt": null,
          "userNotes": "",
          "enhancedNotes": "",
          "createdAt": "2026-03-19T09:10:00.000Z",
          "updatedAt": "2026-03-19T09:20:00.000Z",
          "workspaceId": "workspace-1",
          "speakers": {
            "spk_1": "面试官",
            "spk_2": "候选人"
          },
          "segments": [
            {
              "id": "segment-1",
              "speaker": "spk_1",
              "text": "请做个自我介绍。",
              "startTime": 0,
              "endTime": 1800,
              "isFinal": true,
              "order": 0
            }
          ],
          "chatMessages": [],
          "hasAudio": false,
          "audioUrl": null
        }
        """

        let meeting = try APIClient.makeJSONDecoder().decode(
            RemoteMeetingDetail.self,
            from: Data(payload.utf8)
        )

        #expect(meeting.speakers == [
            "spk_1": "面试官",
            "spk_2": "候选人",
        ])
    }

    @Test
    func transcriptPayloadUsesSpeakerDisplayNames() {
        let meeting = Meeting(
            segments: [
                TranscriptSegment(
                    id: "segment-1",
                    speaker: "spk_1",
                    text: "请做个自我介绍。",
                    startTime: 0,
                    endTime: 1800,
                    orderIndex: 0
                ),
                TranscriptSegment(
                    id: "segment-2",
                    speaker: "spk_2",
                    text: "我叫李雷。",
                    startTime: 2000,
                    endTime: 3200,
                    orderIndex: 1
                ),
            ]
        )
        meeting.speakers = [
            "spk_1": "面试官",
            "spk_2": "候选人",
        ]

        let payload = MeetingPayloadMapper.makeMeetingUpsertPayload(
            from: meeting,
            workspaceID: "workspace-1"
        )

        #expect(payload.speakers == [
            "spk_1": "面试官",
            "spk_2": "候选人",
        ])
        #expect(MeetingPayloadMapper.transcriptText(from: meeting) == """
        [面试官]: 请做个自我介绍。
        [候选人]: 我叫李雷。
        """)
    }

    @Test
    func meetingFallsBackToGeneratedSpeakerLabel() {
        let meeting = Meeting()
        meeting.speakers = [:]

        #expect(meeting.displayName(forSpeaker: "spk_3") == "说话人 3")
        #expect(meeting.displayName(forSpeaker: "live_mic") == "live_mic")
    }

    @Test
    func speakerDisplayNameUpdateTrimsAndCanReset() {
        let meeting = Meeting()

        meeting.setDisplayName(" 面试官 ", forSpeaker: "spk_1")
        #expect(meeting.speakers["spk_1"] == "面试官")
        #expect(meeting.displayName(forSpeaker: "spk_1") == "面试官")

        meeting.setDisplayName("   ", forSpeaker: "spk_1")
        #expect(meeting.speakers["spk_1"] == nil)
        #expect(meeting.displayName(forSpeaker: "spk_1") == "说话人 1")
    }

    @Test
    func transcriptSentenceUsesSpeakerDisplayName() {
        let meeting = Meeting(
            segments: [
                TranscriptSegment(
                    id: "segment-1",
                    speaker: "spk_2",
                    text: "我叫李雷。",
                    startTime: 0,
                    endTime: 1800,
                    orderIndex: 0
                )
            ]
        )
        meeting.speakers = [
            "spk_2": "候选人"
        ]

        let sentence = TranscriptSentence.segment(
            meeting.orderedSegments[0],
            in: meeting,
            timeLabel: "00:00"
        )

        #expect(sentence.speakerIdentity?.title == "候选人")
        #expect(sentence.speakerKey == "spk_2")
        #expect(sentence.canRenameSpeaker)
    }
}
