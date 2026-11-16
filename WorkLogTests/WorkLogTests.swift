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

    func testArrowKeysMoveDaysItemsAndDayGrid() {
        XCTAssertEqual(ItemArrow.listIndex(current: nil, count: 3, delta: 1), 0)
        XCTAssertEqual(ItemArrow.listIndex(current: nil, count: 3, delta: -1), 2)
        XCTAssertEqual(ItemArrow.listIndex(current: 1, count: 3, delta: 1), 2)
        XCTAssertEqual(ItemArrow.listIndex(current: 2, count: 3, delta: 1), 2)
        XCTAssertEqual(ItemArrow.listIndex(current: 0, count: 3, delta: -1), 0)

        XCTAssertEqual(ItemArrow.columns(fitting: 800), 2)
        XCTAssertEqual(ItemArrow.gridIndex(current: nil, count: 5, columns: 2, horizontal: 1, vertical: 0), 0)
        XCTAssertEqual(ItemArrow.gridIndex(current: 0, count: 5, columns: 2, horizontal: 1, vertical: 0), 1)
        XCTAssertEqual(ItemArrow.gridIndex(current: 1, count: 5, columns: 2, horizontal: 1, vertical: 0), 2)
        XCTAssertEqual(ItemArrow.gridIndex(current: 1, count: 5, columns: 2, horizontal: 0, vertical: 1), 3)
        XCTAssertEqual(ItemArrow.gridIndex(current: 1, count: 5, columns: 2, horizontal: 0, vertical: -1), 1)
        XCTAssertEqual(ItemArrow.gridIndex(current: 3, count: 5, columns: 2, horizontal: 0, vertical: 1), 4)
    }

    func testDescriptionSuggestionsKeepNewestPrefixMatch() {
        let items = [
            sampleItem("old", day: "2026-10-01", text: "整理接口", order: 0),
            sampleItem("mid", day: "2026-10-20", text: "整理接口", order: 1, type: "需求", sub: "项目需求"),
            sampleItem("newer-same-day", day: "2026-10-20", text: "整理接口", order: 4, type: "技术债务", sub: "慢sql"),
            sampleItem("other", day: "2026-10-28", text: "整理会议纪要", order: 0),
            sampleItem("inside", day: "2026-10-18", text: "周报里整理接口", order: 0),
            sampleItem("early", day: "2026-09-01", text: "整理接口", order: 0),
            sampleItem("self", day: "2026-10-29", text: "整理接口变更", order: 0),
        ]
        let matches = DescriptionSuggestions.make(
            items: items,
            query: " 整理 ",
            startDay: "2026-10-01",
            endDay: "2026-10-30",
            excluding: "self"
        )
        XCTAssertEqual(matches.map(\.description), ["整理会议纪要", "整理接口"])
        XCTAssertEqual(matches[1].typeId, "技术债务")
        XCTAssertEqual(matches[1].subTypeId, "慢sql")
        XCTAssertTrue(DescriptionSuggestions.make(items: items, query: " ", startDay: "2026-10-01", endDay: "2026-10-30", excluding: nil).isEmpty)
    }

    func testDoubleModifierTapNeedsTwoCleanLifts() {
        var detector = DoubleModifierTapDetector(interval: 0.35)
        let start = Date()
        XCTAssertNil(detector.handle(.modifierDown(.command), now: start))
        XCTAssertNil(detector.handle(.modifierUp(.command), now: start.addingTimeInterval(0.05)))
        XCTAssertNil(detector.handle(.modifierDown(.command), now: start.addingTimeInterval(0.10)))
        XCTAssertEqual(detector.handle(.modifierUp(.command), now: start.addingTimeInterval(0.15)), .command)

        var chord = DoubleModifierTapDetector(interval: 0.35)
        XCTAssertNil(chord.handle(.modifierDown(.command), now: start))
        XCTAssertNil(chord.handle(.otherKey, now: start.addingTimeInterval(0.02)))
        XCTAssertNil(chord.handle(.modifierUp(.command), now: start.addingTimeInterval(0.04)))
        XCTAssertNil(chord.handle(.modifierDown(.command), now: start.addingTimeInterval(0.08)))
        XCTAssertNil(chord.handle(.otherKey, now: start.addingTimeInterval(0.10)))
        XCTAssertNil(chord.handle(.modifierUp(.command), now: start.addingTimeInterval(0.12)))
        XCTAssertEqual(QuickHotKey.doubleTap(.option).label, "双击 ⌥")
    }

    func testLegacyItemDecodesWithoutSource() throws {
        let json = """
        {"id":"i1","date":"2026-10-24","description":"记一笔","note":"","typeId":"","subTypeId":"","order":0}
        """
        let item = try JSONDecoder().decode(WorkItem.self, from: Data(json.utf8))
        XCTAssertNil(item.source)
        XCTAssertNil(item.materialTs)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        XCTAssertNil(object?["source"])
        XCTAssertNil(object?["materialTs"])
    }

    func testMaterialTimestampKeepsTheCanonicalForm() {
        XCTAssertTrue(WorkStamp.isCanonical(WorkStamp.isoNow()))
        XCTAssertTrue(WorkStamp.isCanonical("2026-11-13T10:00:00Z"))
        XCTAssertFalse(WorkStamp.isCanonical("2026-11-13T10:00:00+00:00"))
        XCTAssertFalse(WorkStamp.isCanonical("2026-11-13T10:00:00.000Z"))
        XCTAssertFalse(WorkStamp.isCanonical("2026-11-13"))
    }

    func testInboxAppliesNewUpdateAndDelete() throws {
        let day = "2026-11-13"
        let manual = WorkItem(id: "imanual0001", date: day, description: "手写", note: "", typeId: "", subTypeId: "", order: 0, source: "manual", materialTs: "2026-11-13T08:00:00Z")
        let tool = WorkItem(id: "itool000001", date: day, description: "旧标题", note: "旧摘要", typeId: "t1", subTypeId: "s1", order: 1, source: "pi", materialTs: "2026-11-13T09:00:00Z")
        let legacy = WorkItem(id: "ilegacy0001", date: day, description: "旧数据", note: "", typeId: "", subTypeId: "", order: 2)
        let ops = [
            Inbox.Op(op: "new", id: nil, description: "排查合同", note: "摘要", typeId: "tcd4ec2d71f", subTypeId: "s1f68800e8c", source: "pi", materialTs: "2026-11-13T10:00:00Z"),
            Inbox.Op(op: "update", id: "itool000001", description: "新标题", note: "新摘要", typeId: nil, subTypeId: nil, source: "pi", materialTs: "2026-11-13T12:00:00Z"),
            Inbox.Op(op: "delete", id: "imanual0001", description: nil, note: nil, typeId: nil, subTypeId: nil, source: nil, materialTs: nil)
        ]
        let result = try Inbox.apply(ops: ops, date: day, to: [manual, tool, legacy], makeID: { "i0123456789" })
        XCTAssertTrue(result.contains { $0.id == "imanual0001" })
        let updated = try XCTUnwrap(result.first { $0.id == "itool000001" })
        XCTAssertEqual(updated.description, "新标题")
        XCTAssertEqual(updated.note, "新摘要")
        XCTAssertEqual(updated.typeId, "t1")
        XCTAssertEqual(updated.subTypeId, "s1")
        XCTAssertEqual(updated.date, day)
        XCTAssertEqual(updated.materialTs, "2026-11-13T12:00:00Z")
        let created = try XCTUnwrap(result.first { $0.id == "i0123456789" })
        XCTAssertEqual(created.id.count, 11)
        XCTAssertTrue(created.id.hasPrefix("i"))
        XCTAssertEqual(created.source, "pi")
        XCTAssertEqual(created.materialTs, "2026-11-13T10:00:00Z")
        XCTAssertTrue(result.contains { $0.id == "ilegacy0001" })
        let dayItems = result.filter { $0.date == day }.sorted { $0.order < $1.order }
        XCTAssertEqual(dayItems.last?.id, "i0123456789")
    }

    func testInboxKeepsHandwrittenItemsAndContinues() throws {
        let day = "2026-11-13"
        let handwritten = WorkItem(id: "i1", date: day, description: "手写的", note: "", typeId: "", subTypeId: "", order: 0, source: "manual", materialTs: "2026-11-13T08:00:00Z")
        let tool = WorkItem(id: "i2", date: day, description: "工具写的", note: "", typeId: "", subTypeId: "", order: 1, source: "pi", materialTs: "2026-11-13T09:00:00Z")
        let legacy = WorkItem(id: "i3", date: day, description: "老数据", note: "", typeId: "", subTypeId: "", order: 2)

        let refusedManual = try Inbox.apply(ops: [deleteOp("i1")], date: day, to: [handwritten, tool], makeID: { "i0123456789" })
        XCTAssertEqual(refusedManual.map(\.description), ["手写的", "工具写的"])

        let refusedLegacy = try Inbox.apply(ops: [deleteOp("i3")], date: day, to: [legacy, tool], makeID: { "i0123456789" })
        XCTAssertEqual(refusedLegacy.map(\.description), ["老数据", "工具写的"])

        let removedTool = try Inbox.apply(ops: [deleteOp("i2")], date: day, to: [handwritten, tool], makeID: { "i0123456789" })
        XCTAssertEqual(removedTool.map(\.description), ["手写的"])

        let mixed = try Inbox.apply(ops: [deleteOp("i2"), deleteOp("i1")], date: day, to: [handwritten, tool], makeID: { "i0123456789" })
        XCTAssertEqual(mixed.map(\.description), ["手写的"])

        let continued = try Inbox.apply(
            ops: [
                deleteOp("i1"),
                Inbox.Op(op: "new", id: nil, description: "新条目", note: nil, typeId: nil, subTypeId: nil, source: "pi", materialTs: "2026-11-13T10:00:00Z")
            ],
            date: day,
            to: [handwritten],
            makeID: { "i0123456789" }
        )
        XCTAssertEqual(continued.map(\.description), ["手写的", "新条目"])
    }

    private func deleteOp(_ id: String) -> Inbox.Op {
        Inbox.Op(op: "delete", id: id, description: nil, note: nil, typeId: nil, subTypeId: nil, source: nil, materialTs: nil)
    }

    func testInboxSkipsStaleOrBadUpdatesButKeepsLaterOps() throws {
        let day = "2026-11-13"
        let future = WorkItem(id: "ifuture0001", date: day, description: "保持", note: "原备注", typeId: "t1", subTypeId: "", order: 0, source: "pi", materialTs: "2026-11-13T18:00:00Z")
        let equal = WorkItem(id: "iequal00001", date: day, description: "相等", note: "", typeId: "", subTypeId: "", order: 1, source: "pi", materialTs: "2026-11-13T10:00:00Z")
        let plain = WorkItem(id: "iplain00001", date: day, description: "原标题", note: "", typeId: "", subTypeId: "", order: 2, source: "pi", materialTs: "2026-11-13T08:00:00Z")
        let ops = [
            Inbox.Op(op: "update", id: "ifuture0001", description: "旧内容", note: "旧备注", typeId: nil, subTypeId: nil, source: "pi", materialTs: "2026-11-13T10:00:00Z"),
            Inbox.Op(op: "update", id: "iequal00001", description: "改写", note: nil, typeId: nil, subTypeId: nil, source: "pi", materialTs: "2026-11-13T10:00:00Z"),
            Inbox.Op(op: "update", id: "iplain00001", description: "坏时间", note: nil, typeId: nil, subTypeId: nil, source: nil, materialTs: "2026-11-13T10:00:00.000Z"),
            Inbox.Op(op: "update", id: "iplain00001", description: "没时间", note: nil, typeId: nil, subTypeId: nil, source: nil, materialTs: nil),
            Inbox.Op(op: "new", id: nil, description: "后面这条要在", note: nil, typeId: nil, subTypeId: nil, source: "pi", materialTs: "2026-11-13T11:00:00Z")
        ]
        let result = try Inbox.apply(ops: ops, date: day, to: [future, equal, plain], makeID: { "i0123456789" })
        XCTAssertEqual(result.first { $0.id == "ifuture0001" }?.description, "保持")
        XCTAssertEqual(result.first { $0.id == "ifuture0001" }?.note, "原备注")
        XCTAssertEqual(result.first { $0.id == "ifuture0001" }?.materialTs, "2026-11-13T18:00:00Z")
        XCTAssertEqual(result.first { $0.id == "iequal00001" }?.description, "相等")
        XCTAssertEqual(result.first { $0.id == "iplain00001" }?.description, "原标题")
        XCTAssertEqual(result.first { $0.id == "i0123456789" }?.description, "后面这条要在")
    }

    func testInboxRejectsNewThatCarriesAnID() {
        let op = Inbox.Op(op: "new", id: "i0123456789", description: "不该写入", note: nil, typeId: nil, subTypeId: nil, source: "pi", materialTs: "2026-11-13T10:00:00Z")
        XCTAssertThrowsError(try Inbox.apply(ops: [op], date: "2026-11-13", to: [], makeID: { "ishouldnot1" }))
    }

    func testInboxAndDoneAreNotMonthsAndBadFileRestores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LogStore(root: root)
        try store.saveMonth("2026-10", items: [
            WorkItem(id: "i1", date: "2026-10-24", description: "记一笔", note: "", typeId: "", subTypeId: "", order: 0)
        ])
        let inbox = root.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: inbox.appendingPathComponent("2026-11-14.json.processing"))
        let file = inbox.appendingPathComponent("2026-11-13.json")
        try Data("{".utf8).write(to: file)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("done"), withIntermediateDirectories: true)
        XCTAssertEqual(store.monthsOnDisk(), ["2026-10"])
        XCTAssertEqual(store.inboxJSONFiles().map(\.lastPathComponent), ["2026-11-13.json"])
        let claimed = try store.claimInboxFile(file)
        XCTAssertTrue(store.inboxJSONFiles().isEmpty)
        XCTAssertEqual(claimed.lastPathComponent, "2026-11-13.json.processing")
        XCTAssertThrowsError(try JSONDecoder().decode(Inbox.Payload.self, from: Data(contentsOf: claimed)))
        try store.restoreInboxFile(claimed)
        XCTAssertEqual(store.inboxJSONFiles().map(\.lastPathComponent), ["2026-11-13.json"])
        let again = try store.claimInboxFile(store.inboxJSONFiles()[0])
        try store.archiveInboxFile(again, day: "2026-11-13", clock: "101530")
        XCTAssertTrue(store.inboxJSONFiles().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("done/2026-11-13-101530.json").path))
        XCTAssertEqual(store.monthsOnDisk(), ["2026-10"])
        try FileManager.default.removeItem(at: root)
    }

    private func sampleItem(_ id: String, day: String, text: String, order: Int, type: String = "", sub: String = "") -> WorkItem {
        WorkItem(id: id, date: day, description: text, note: "", typeId: type, subTypeId: sub, order: order)
    }
}
