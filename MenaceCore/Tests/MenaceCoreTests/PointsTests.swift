import XCTest
@testable import MenaceCore

final class PointsTests: XCTestCase {
    let utc = DayClock(timeZone: TimeZone(identifier: "UTC")!)
    /// Monday 2026-09-21 10:00 UTC.
    let monday = ISO8601DateFormatter().date(from: "2026-09-21T10:00:00Z")!

    func makeGame(points: Int = 100) -> Game {
        var g = Game(state: PetState(now: monday), days: utc)
        _ = g.tick(now: monday)
        g.state.points.total = points
        return g
    }

    func play(_ g: inout Game, at now: Date) -> Outcome {
        guard case .success(let session) = g.startActivity(.snackToss, now: now) else {
            XCTFail("could not start")
            return Outcome(reaction: .busy, refusal: .busy, events: [])
        }
        return g.finishActivity(session, result: ActivityResult(kind: .snackToss, quality: 0.5, score: 3, won: true), now: now)
    }

    func testGainsMatchXPAndAreLogged() {
        var g = makeGame(points: 0)
        g.state.needs.fullness = 40
        let out = g.feed(now: monday)
        XCTAssertTrue(out.events.contains(.points(Tuning.feedXP, .fed)))
        _ = play(&g, at: monday.addingTimeInterval(60))
        XCTAssertEqual(g.state.points.total, g.state.xp, "with no losses, points equal XP")
        XCTAssertEqual(g.state.points.history.first?.reason, .fed)
        XCTAssertEqual(g.state.points.gainedToday, g.state.xp)
    }

    func testRepeatsMergeIntoOneHistoryLine() {
        var g = makeGame()
        for i in 0..<3 { _ = g.pet(now: monday.addingTimeInterval(Double(i) * 5)) }
        let petted = g.state.points.history.filter { $0.reason == .petted }
        XCTAssertEqual(petted.count, 1)
        XCTAssertEqual(petted.first?.count, 3)
        XCTAssertEqual(petted.first?.amount, 3 * Tuning.petXP)
    }

    func testForceFeedingCosts() {
        var g = makeGame()
        g.state.needs.fullness = Tuning.refuseFoodAt
        let out = g.feed(now: monday)
        XCTAssertEqual(out.refusal, .full)
        XCTAssertTrue(out.events.contains(.points(-Tuning.forceFedPenalty, .forceFed)))
        XCTAssertEqual(g.state.points.total, 100 - Tuning.forceFedPenalty)
    }

    func testEarlyWakeCosts() {
        var g = makeGame()
        g.state.needs.energy = 30
        _ = g.sleep(now: monday)
        let out = g.wake(now: monday.addingTimeInterval(60))
        XCTAssertTrue(out.events.contains(.points(-Tuning.wokeEarlyPenalty, .wokeEarly)))
        XCTAssertEqual(g.state.xp, 0, "XP is never taken away")
    }

    func testPokingTooFastAnnoysAndCosts() {
        var g = makeGame()
        for i in 0..<Tuning.pokesAllowed { XCTAssertEqual(g.pet(now: monday.addingTimeInterval(Double(i))).reaction, .touch) }
        let out = g.pet(now: monday.addingTimeInterval(Double(Tuning.pokesAllowed)))
        XCTAssertEqual(out.reaction, .annoyed)
        XCTAssertTrue(out.events.contains(.points(-Tuning.pokePenalty, .poked)))
        // After a breather it is happy again.
        XCTAssertEqual(g.pet(now: monday.addingTimeInterval(Tuning.pokeWindow + 30)).reaction, .touch)
    }

    func testPlayingWornOutCosts() {
        var g = makeGame()
        g.state.needs.energy = Tuning.wornOutBelow - 5
        let out = play(&g, at: monday)
        XCTAssertTrue(out.events.contains(.points(-Tuning.wornOutPenalty, .wornOut)))
        XCTAssertTrue(out.events.contains { if case .points(let n, .played) = $0 { return n > 0 }; return false })
    }

    func testHungerCostsPerWholeHour() {
        var g = makeGame()
        g.state.needs.fullness = Tuning.hungryBelow - 1
        let events = g.tick(now: monday.addingTimeInterval(2.5 * 3600))
        XCTAssertTrue(events.contains(.points(-2 * Tuning.hungryPenaltyPerHour, .hungry)))
        XCTAssertEqual(g.state.points.hungryHours, 0.5, accuracy: 0.001)
        // Feeding clears the partial hour.
        _ = g.feed(now: monday.addingTimeInterval(2.5 * 3600))
        XCTAssertEqual(g.state.points.hungryHours, 0)
    }

    func testHungerOnlyCountsTimeBelowTheLine() {
        // 8 per hour from 41 reaches 25 after 2 hours; 3 more hours are hungry.
        XCTAssertEqual(TimeModel.hoursBelow(25, start: 41, rate: 8, floor: 20, hours: 5), 3, accuracy: 0.001)
        XCTAssertEqual(TimeModel.hoursBelow(25, start: 41, rate: 8, floor: 20, hours: 1), 0)
        XCTAssertEqual(TimeModel.hoursBelow(25, start: 41, rate: 8, floor: 30, hours: 9), 0, "a floor above the line")
        XCTAssertEqual(TimeModel.hoursBelow(25, start: 10, rate: 8, floor: 20, hours: 2), 2)
    }

    func testLossesStopAtZeroAndAtTheDailyCap() {
        var g = makeGame(points: 3)
        g.state.needs.fullness = Tuning.refuseFoodAt
        _ = g.feed(now: monday)
        _ = g.feed(now: monday)
        XCTAssertEqual(g.state.points.total, 0)
        XCTAssertEqual(g.state.points.lostToday, 3)

        var h = makeGame(points: 1000)
        h.state.needs.fullness = Tuning.refuseFoodAt
        for _ in 0..<100 { _ = h.feed(now: monday) }
        XCTAssertEqual(h.state.points.lostToday, Tuning.maxPointsLostPerDay)
        XCTAssertEqual(h.state.points.total, 1000 - Tuning.maxPointsLostPerDay)
        let tomorrow = monday.addingTimeInterval(86400)
        _ = h.tick(now: tomorrow)
        h.state.needs.fullness = Tuning.refuseFoodAt
        _ = h.feed(now: tomorrow)
        XCTAssertEqual(h.state.points.lostToday, Tuning.forceFedPenalty, "a new day, a new cap")
    }

    func testHistoryIsCapped() {
        var book = PointsBook()
        book.total = 1000
        for i in 0..<100 {
            book.apply(i % 2 == 0 ? 1 : -1, i % 2 == 0 ? .fed : .forceFed, day: "d\(i / 10)", at: monday)
        }
        XCTAssertEqual(book.history.count, Tuning.pointsHistoryLimit)
    }

    func testOldSavesStartPointsAtXPAndSkipTheGuide() throws {
        let json = #"{"version":1,"state":{"lastSimulated":1790000000,"xp":50}}"#
        let s = try SaveCodec.decode(Data(json.utf8))
        XCTAssertEqual(s.points.total, 50)
        XCTAssertTrue(s.howToPlayShown)
        XCTAssertFalse(PetState(now: monday).howToPlayShown, "a brand-new player sees the guide")
    }

    func testStartOverClearsPointsButRemembersTheGuide() {
        var g = makeGame(points: 500)
        g.state.howToPlayShown = true
        g.reset(now: monday)
        XCTAssertEqual(g.state.points.total, 0)
        XCTAssertTrue(g.state.howToPlayShown)
    }

    func testPointsToNextLevel() {
        var s = PetState(now: monday)
        XCTAssertEqual(s.pointsToNextLevel, Tuning.xpForLevel(2))
        s.xp = Tuning.xpForLevel(4) + 10
        XCTAssertEqual(s.level, 4)
        XCTAssertEqual(s.pointsToNextLevel, Tuning.xpForLevel(5) - s.xp)
    }

    func testEveryReasonHasARule() {
        for r in PointReason.allCases {
            XCTAssertFalse(r.rule.isEmpty)
            XCTAssertEqual(r.rule.hasPrefix("−"), r.isPenalty, r.rawValue)
        }
    }
}
