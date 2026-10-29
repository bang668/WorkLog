import XCTest
@testable import WorkLog

final class WorkLogTests: XCTestCase {
    private var calendar: Calendar {
        WorkCalendar.gregorian(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    }

    func testWeekOfOctober24() {
        XCTAssertEqual(WorkCalendar.isoWeek(of: "2026-10-24", calendar: calendar), 43)
        XCTAssertEqual(WorkCalendar.startOfWeek(containing: "2026-10-24", calendar: calendar), "2026-10-19")
        XCTAssertEqual(WorkCalendar.weekDays(containing: "2026-10-24", calendar: calendar), [
            "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"
        ])
        XCTAssertEqual(WorkCalendar.weekdayName(of: "2026-10-24", calendar: calendar), "周六")
        XCTAssertEqual(WorkCalendar.monthDayHyphen("2026-10-24"), "10-24")
        XCTAssertEqual(WorkCalendar.chineseYearMonthDay("2026-01-05"), "2026年01月05日")
        XCTAssertEqual(WorkCalendar.chineseMonthDay("2026-01-05"), "01月05日")
        XCTAssertEqual(WorkCalendar.chineseYearMonth("2026-01"), "2026年01月")
        XCTAssertEqual(WorkCalendar.weekRangeLabel(days: WorkCalendar.weekDays(containing: "2026-10-24", calendar: calendar)), "2026年10月19日 – 10月25日")
    }

    func testOctoberGridIncludesNeighborDays() {
        let weeks = WorkCalendar.weeks(inMonth: "2026-10", calendar: calendar)
        XCTAssertEqual(weeks.first?.first, "2026-09-28")
        XCTAssertEqual(weeks.last?.last, "2026-11-01")
        XCTAssertEqual(WorkCalendar.monthDayHyphen("2026-09-28"), "09-28")
        XCTAssertEqual(WorkCalendar.monthDayHyphen("2026-11-01"), "11-01")
    }

    func testVisibleMonthsGrowFromStartMonth() {
        XCTAssertEqual(
            MonthTree.visibleMonths(startMonth: "2026-10", todayMonth: "2026-10", monthsWithItems: []),
            ["2026-10"]
        )
        XCTAssertEqual(
            MonthTree.visibleMonths(startMonth: "2026-10", todayMonth: "2027-01", monthsWithItems: ["2026-12"]),
            ["2026-10", "2026-11", "2026-12", "2027-01"]
        )
        XCTAssertEqual(
            MonthTree.visibleMonths(startMonth: "2026-10", todayMonth: "2026-10", monthsWithItems: ["2026-08"]),
            ["2026-08", "2026-10"]
        )
    }

    func testWeekendColumns() {
        XCTAssertFalse(ColumnLayout.weekIsSlim(index: 4, itemCount: 0))
        XCTAssertTrue(ColumnLayout.weekIsSlim(index: 6, itemCount: 0))
        XCTAssertFalse(ColumnLayout.weekIsSlim(index: 5, itemCount: 1))
        let weeks = [["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]]
        let slim = ColumnLayout.monthSlimColumns(weeks: weeks, viewMonth: "2026-10") { day in
            day == "2026-10-24" ? 1 : 0
        }
        XCTAssertFalse(slim.saturday)
        XCTAssertTrue(slim.sunday)
    }

    func testMarkdownOmitsEmptyDaysAndTypes() {
        let items = [
            WorkItem(id: "i1", date: "2026-10-23", description: "完成登录页改版", note: "等待设计确认空状态", typeId: "t1", subTypeId: "t1a", order: 0),
            WorkItem(id: "i2", date: "2026-10-23", description: "排查导出乱码", note: "", typeId: "", subTypeId: "", order: 1),
            WorkItem(id: "i3", date: "2026-10-22", description: "整理本周接口变更", note: "", typeId: "t2", subTypeId: "", order: 0)
        ]
        let types = [
            WorkType(id: "t1", name: "开发", order: 0, children: [SubType(id: "t1a", name: "界面", order: 0)]),
            WorkType(id: "t2", name: "沟通", order: 1, children: [])
        ]
        let text = MarkdownExport.document(scope: .month("2026-10"), items: items, types: types)
        XCTAssertEqual(text, """
        # 2026-10

        ## 2026-10-22 周四

        - 日期：2026-10-22
          一级类型：沟通
          二级类型：
          事项描述：整理本周接口变更
          备注：

        ## 2026-10-23 周五

        - 日期：2026-10-23
          一级类型：开发
          二级类型：界面
          事项描述：完成登录页改版
          备注：等待设计确认空状态

        - 日期：2026-10-23
          一级类型：
          二级类型：
          事项描述：排查导出乱码
          备注：

        """)
        XCTAssertNil(MarkdownExport.document(scope: .month("2026-11"), items: items, types: types))
    }

    func testDeletedTypeExportsWithoutLabel() {
        let item = WorkItem(id: "i1", date: "2026-10-23", description: "排查导出乱码", note: "", typeId: "gone", subTypeId: "gone2", order: 0)
        let text = MarkdownExport.document(scope: .quarter(year: 2026, quarter: 4), items: [item], types: [])
        XCTAssertTrue(text?.contains("# 2026-Q4") == true)
        XCTAssertTrue(text?.contains("事项描述：排查导出乱码") == true)
        XCTAssertTrue(text?.contains("一级类型：") == true)
        XCTAssertFalse(text?.contains("gone") == true)
    }

    func testMarkdownKeepsMarkersAndNewlinesInsideTheField() {
        let item = WorkItem(
            id: "i1",
            date: "2026-10-23",
            description: "使用 *强调* 和 `代码` 以及 \\n",
            note: "第一行\n# 这不是标题\n- 这也不是下一条",
            typeId: "",
            subTypeId: "",
            order: 0
        )
        let text = MarkdownExport.document(scope: .month("2026-10"), items: [item], types: [])
        XCTAssertEqual(text, """
        # 2026-10

        ## 2026-10-23 周五

        - 日期：2026-10-23
          一级类型：
          二级类型：
          事项描述：使用 \\*强调\\* 和 \\`代码\\` 以及 \\\\n
          备注：第一行\\n\\# 这不是标题\\n\\- 这也不是下一条

        """)
    }

    func testPlainLogImportReadsIndentedDays() {
        let text = """
        2026-10-22
        \tfastjson版本升级
        \t国际散航采购开发
        2026-10-23
        \tHermes版本整理
        \tAI运价识别

        """
        XCTAssertEqual(PlainLogImport.parse(text), .success([
            PlainLogImport.Entry(date: "2026-10-22", description: "fastjson版本升级"),
            PlainLogImport.Entry(date: "2026-10-22", description: "国际散航采购开发"),
            PlainLogImport.Entry(date: "2026-10-23", description: "Hermes版本整理"),
            PlainLogImport.Entry(date: "2026-10-23", description: "AI运价识别")
        ]))
    }

    func testPlainLogImportSkipsTheSameDescriptionOnThatDay() {
        let existing = [PlainLogImport.Entry(date: "2026-10-22", description: "fastjson版本升级")]
        let incoming = [
            PlainLogImport.Entry(date: "2026-10-22", description: "fastjson版本升级"),
            PlainLogImport.Entry(date: "2026-10-22", description: "fastjson版本升级"),
            PlainLogImport.Entry(date: "2026-10-22", description: "国际散航采购开发"),
            PlainLogImport.Entry(date: "2026-10-23", description: "fastjson版本升级")
        ]
        let result = PlainLogImport.skippingExisting(incoming, existing: existing)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(result.added, [
            PlainLogImport.Entry(date: "2026-10-22", description: "国际散航采购开发"),
            PlainLogImport.Entry(date: "2026-10-23", description: "fastjson版本升级")
        ])
    }

    func testPlainLogImportRejectsALooseLine() {
        XCTAssertEqual(PlainLogImport.parse("2026-02-31\n\t没有这一天"), .failure(.badLine(1)))
        XCTAssertEqual(PlainLogImport.parse("\t还没有日期"), .failure(.badLine(1)))
        XCTAssertEqual(PlainLogImport.parse("2026-10-22\n没有缩进"), .failure(.badLine(2)))
        XCTAssertEqual(PlainLogImport.parse("2026-10-22\n"), .failure(.empty))
    }

    func testStoreRoundTripAndCorruptFileIsLeftAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LogStore(root: root)
        let library = LibraryIndex(startMonth: "2026-10", openedMonths: ["2026-08"])
        try store.saveLibrary(library)
        try store.saveTypes([WorkType(id: "t1", name: "开发", order: 0, children: [])])
        let item = WorkItem(id: "i1", date: "2026-10-24", description: "记一笔", note: "备注", typeId: "t1", subTypeId: "", order: 0)
        try store.saveMonth("2026-10", items: [item])
        XCTAssertEqual(try store.loadLibrary(), library)
        XCTAssertEqual(try store.loadMonth("2026-10"), [item])
        XCTAssertEqual(try store.loadMonth("2026-11"), [])
        XCTAssertEqual(store.monthsOnDisk(), ["2026-10"])

        let monthURL = root.appendingPathComponent("2026").appendingPathComponent("10.json")
        let broken = Data("{".utf8)
        try broken.write(to: monthURL)
        XCTAssertThrowsError(try store.loadMonth("2026-10"))
        XCTAssertEqual(try Data(contentsOf: monthURL), broken)

        try store.saveMonth("2026-10", items: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: monthURL.path))
        try FileManager.default.removeItem(at: root)
    }

    func testTypeDragLandsInTheGapItIsMovingToward() {
        let slots = [
            CGRect(x: 0, y: 0, width: 200, height: 100),
            CGRect(x: 0, y: 112, width: 200, height: 100),
            CGRect(x: 0, y: 224, width: 200, height: 100)
        ]
        let mids = slots.map(\.midY)
        XCTAssertEqual(TypeDragLayout.landingIndex(origin: 1, midYs: mids, y: slots[1].midY), 1)
        XCTAssertEqual(TypeDragLayout.landingIndex(origin: 1, midYs: mids, y: slots[2].midY + 1), 2)
        XCTAssertEqual(TypeDragLayout.landingIndex(origin: 1, midYs: mids, y: slots[0].midY - 1), 0)
        XCTAssertEqual(TypeDragLayout.shift(index: 2, origin: 1, destination: 2, distance: 112), -112)
        XCTAssertEqual(TypeDragLayout.shift(index: 0, origin: 1, destination: 0, distance: 112), 112)
        XCTAssertEqual(TypeDragLayout.holeMinY(origin: 1, destination: 2, slots: slots, spacing: 12), 224)
        XCTAssertEqual(TypeDragLayout.holeMinY(origin: 1, destination: 0, slots: slots, spacing: 12), 0)

        let uneven = [
            CGRect(x: 0, y: 0, width: 200, height: 80),
            CGRect(x: 0, y: 92, width: 200, height: 200),
            CGRect(x: 0, y: 304, width: 200, height: 40)
        ]
        XCTAssertEqual(TypeDragLayout.holeMinY(origin: 1, destination: 2, slots: uneven, spacing: 12), 144)
    }

    func testTagDragFollowsRowsThenCenters() {
        let slots = [
            CGRect(x: 0, y: 0, width: 40, height: 22),
            CGRect(x: 46, y: 0, width: 40, height: 22),
            CGRect(x: 92, y: 0, width: 40, height: 22),
            CGRect(x: 0, y: 28, width: 40, height: 22)
        ]
        let onSecond = CGPoint(x: slots[2].midX, y: slots[2].midY)
        XCTAssertEqual(TypeDragLayout.tagLandingIndex(origin: 0, slots: slots, point: onSecond), 1)
        let pastSecond = CGPoint(x: slots[2].maxX - 1, y: slots[2].midY)
        XCTAssertEqual(TypeDragLayout.tagLandingIndex(origin: 0, slots: slots, point: pastSecond), 2)
        let beforeLast = CGPoint(x: slots[3].minX + 2, y: slots[3].midY)
        XCTAssertEqual(TypeDragLayout.tagLandingIndex(origin: 0, slots: slots, point: beforeLast), 2)
        let afterLast = CGPoint(x: slots[3].maxX - 1, y: slots[3].midY)
        XCTAssertEqual(TypeDragLayout.tagLandingIndex(origin: 0, slots: slots, point: afterLast), 3)
    }

    func testTagOffsetsSlideNeighborsWhileDragging() {
        let slots = [
            CGRect(x: 10, y: 20, width: 40, height: 22),
            CGRect(x: 56, y: 20, width: 30, height: 22),
            CGRect(x: 92, y: 20, width: 50, height: 22)
        ]
        let offsets = TypeDragLayout.tagOffsets(origin: 0, destination: 2, slots: slots, width: 200, spacing: 6)
        XCTAssertEqual(offsets[1].width, -46, accuracy: 0.1)
        XCTAssertEqual(offsets[2].width, -46, accuracy: 0.1)
        XCTAssertEqual(offsets[0].width, 92, accuracy: 0.1)
        XCTAssertEqual(offsets[0].height, 0, accuracy: 0.1)
    }

    func testDraggedItemLeavesTheListAndTheGapTakesTheLandingSlot() {
        let ids = ["a", "b", "c"]
        let day = "2026-10-25"
        XCTAssertEqual(
            ItemDragSlots.ids(itemIDs: ids, draggingID: "b", preview: ItemDragPreview(itemID: "b", day: day, beforeID: "b"), day: day),
            ["a", "gap", "c"]
        )
        XCTAssertEqual(
            ItemDragSlots.ids(itemIDs: ids, draggingID: "b", preview: ItemDragPreview(itemID: "b", day: day, beforeID: "a"), day: day),
            ["gap", "a", "c"]
        )
        XCTAssertEqual(
            ItemDragSlots.ids(itemIDs: ids, draggingID: "b", preview: ItemDragPreview(itemID: "b", day: day, beforeID: nil), day: day),
            ["a", "c", "gap"]
        )
        XCTAssertEqual(
            ItemDragSlots.ids(itemIDs: ids, draggingID: "b", preview: ItemDragPreview(itemID: "b", day: "2026-10-26", beforeID: nil), day: day),
            ["a", "c"]
        )
    }

    func testDayDragMovesAfterAShortTravelTowardTheNextCard() {
        let slots = [
            DayCardSlot(id: "a", frame: CGRect(x: 0, y: 0, width: 260, height: 168)),
            DayCardSlot(id: "b", frame: CGRect(x: 272, y: 0, width: 260, height: 168)),
            DayCardSlot(id: "c", frame: CGRect(x: 544, y: 0, width: 260, height: 168)),
            DayCardSlot(id: "d", frame: CGRect(x: 0, y: 180, width: 260, height: 168))
        ]
        let origin = CGPoint(x: 40, y: 40)
        XCTAssertEqual(DayDragLayout.steps(47, pitch: 272), 0)
        XCTAssertEqual(DayDragLayout.steps(48, pitch: 272), 1)
        XCTAssertEqual(DayDragLayout.steps(48 + 272, pitch: 272), 2)
        XCTAssertEqual(DayDragLayout.steps(-48, pitch: 180), -1)
        XCTAssertEqual(
            DayDragLayout.landingID(pointer: CGPoint(x: origin.x + 47, y: origin.y), origin: origin, slots: slots, draggingID: "a"),
            "a"
        )
        XCTAssertEqual(
            DayDragLayout.landingID(pointer: CGPoint(x: origin.x + 48, y: origin.y), origin: origin, slots: slots, draggingID: "a"),
            "b"
        )
        XCTAssertEqual(
            DayDragLayout.landingID(pointer: CGPoint(x: origin.x + 48 + 272, y: origin.y), origin: origin, slots: slots, draggingID: "a"),
            "c"
        )
        XCTAssertEqual(
            DayDragLayout.landingID(pointer: CGPoint(x: origin.x, y: origin.y + 48), origin: origin, slots: slots, draggingID: "a"),
            "d"
        )
        XCTAssertNil(
            DayDragLayout.landingID(pointer: CGPoint(x: origin.x, y: origin.y + 48 + 180), origin: origin, slots: slots, draggingID: "d")
        )
    }
}
