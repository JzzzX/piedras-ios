import Testing
@testable import piedras

struct MarkdownDocumentFormatterTests {
    @Test
    func parsesOrderedListIntoDedicatedBlocks() {
        let blocks = MarkdownDocumentFormatter.blocks(
            from: """
            1. 第一项
            2. 第二项

            **依据说明：** 这里是补充说明。
            """
        )

        #expect(blocks.count == 3)

        guard blocks.count == 3 else { return }

        switch blocks[0].kind {
        case let .orderedList(index):
            #expect(index == 1)
        default:
            Issue.record("第一项应被识别为有序列表")
        }

        switch blocks[1].kind {
        case let .orderedList(index):
            #expect(index == 2)
        default:
            Issue.record("第二项应被识别为有序列表")
        }

        switch blocks[2].kind {
        case .paragraph:
            #expect(blocks[2].plainText == "依据说明： 这里是补充说明。")
        default:
            Issue.record("加粗说明段应保留为普通段落块")
        }
    }
}
