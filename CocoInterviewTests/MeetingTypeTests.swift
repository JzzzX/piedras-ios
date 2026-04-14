import Testing
@testable import CocoInterview

struct MeetingTypeTests {
    @Test
    func supportedMeetingTypesMatchExpectedOrder() {
        #expect(MeetingTypeOption.allCases.map(\.rawValue) == [
            "通用",
            "访谈",
            "演讲",
            "头脑风暴",
            "项目周会",
            "需求评审",
            "销售沟通",
            "面试复盘",
        ])
    }

    @Test
    func meetingTypeFallsBackToGeneralForUnknownValue() {
        let meeting = Meeting()

        #expect(meeting.meetingType == "通用")

        meeting.meetingType = "访谈"
        #expect(meeting.meetingType == "访谈")

        meeting.meetingType = "未知类型"
        #expect(meeting.meetingType == "通用")
    }
}
