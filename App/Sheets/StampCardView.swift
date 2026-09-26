import SwiftUI
import MenaceCore

/// This week's stamps, today's challenge, level and discoveries. Icons and numbers only.
struct StampCardView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let s = model.state
        let days = model.game.days
        let today = days.weekdayIndex(model.now)
        let challenge = model.game.todaysChallenge

        ScrollView {
            VStack(spacing: 28) {
                // Week: seven stamps, Monday first. Missed days are just empty.
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let key = dayKey(offset: i - today)
                        let gold = s.stamps.goldDays.contains(key)
                        let stamped = s.stamps.days.contains(key)
                        let letter = ["M", "T", "W", "T", "F", "S", "S"][i]
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(stamped ? (gold ? Color(hex: 0xFFC83D) : Ink.body) : Ink.body.opacity(0.08))
                                if stamped {
                                    Image(systemName: gold ? "star.fill" : "pawprint.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(gold ? Ink.body : Ink.eye)
                                } else {
                                    Text(letter).font(.system(.headline, design: .rounded).weight(.heavy)).dynamicTypeSize(...DynamicTypeSize.xLarge).opacity(0.5)
                                }
                                if i == today { Circle().stroke(Ink.body, lineWidth: 3).padding(-4) }
                            }
                            .frame(width: 42, height: 42)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(s.stamps.days.count) of 7 stamps this week. \(Tuning.stampsForBonus) earns a bonus, \(Tuning.stampsForGift) earns a gift.")

                HStack(spacing: 22) {
                    milestone(count: Tuning.stampsForBonus, symbol: "sparkles", have: s.stamps.days.count)
                    milestone(count: Tuning.stampsForGift, symbol: "gift.fill", have: s.stamps.days.count)
                }

                // Today's challenge.
                HStack(spacing: 14) {
                    Image(systemName: challenge.symbol)
                        .font(.title.weight(.bold))
                        .frame(width: 60, height: 60)
                        .background(Ink.body.opacity(0.08), in: Circle())
                    HStack(spacing: 6) {
                        ForEach(0..<challenge.target, id: \.self) { i in
                            Capsule()
                                .fill(i < min(s.challenge.progress, challenge.target) || s.challenge.completed ? Ink.body : Ink.body.opacity(0.12))
                                .frame(width: challenge.target > 3 ? 14 : 30, height: 10)
                        }
                    }
                    if s.challenge.completed {
                        Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Color(hex: 0x2FBF71))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today: \(challenge.spoken). \(s.challenge.completed ? "Done" : "\(min(s.challenge.progress, challenge.target)) of \(challenge.target)")")

                // Level.
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("\(s.level)").font(.system(.title2, design: .rounded).weight(.heavy))
                        Spacer()
                        Text("\(s.pointsToNextLevel) to Level \(s.level + 1)")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(0.7)
                    }
                    ProgressView(value: levelProgress(s)).tint(Ink.body)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level \(s.level). \(s.pointsToNextLevel) more points to level \(s.level + 1).")

                // Discoveries: found ones show their icon, the rest are mysteries.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(Discovery.allCases, id: \.self) { d in
                        let found = s.discoveries.contains(d.rawValue)
                        Image(systemName: found ? d.symbol : "questionmark")
                            .font(.title3.weight(.bold))
                            .frame(width: 52, height: 52)
                            .background(Ink.body.opacity(found ? 0.12 : 0.04), in: Circle())
                            .opacity(found ? 1 : 0.4)
                            .accessibilityLabel(found ? d.spoken : "Undiscovered")
                    }
                }
            }
            .padding(24)
        }
        .foregroundStyle(Ink.body)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]) // big text needs the full height
        .presentationBackground(Ink.eye)
    }

    private func dayKey(offset: Int) -> String {
        let days = model.game.days
        let date = days.calendar.date(byAdding: .day, value: offset, to: model.now) ?? model.now
        return days.dayKey(date)
    }

    private func milestone(count: Int, symbol: String, have: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text("\(count)").font(.system(.headline, design: .rounded).weight(.heavy))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Ink.body.opacity(have >= count ? 0.9 : 0.08), in: Capsule())
        .foregroundStyle(have >= count ? Ink.eye : Ink.body)
        .accessibilityHidden(true)
    }

    private func levelProgress(_ s: PetState) -> Double {
        let lo = Tuning.xpForLevel(s.level), hi = Tuning.xpForLevel(s.level + 1)
        return Double(s.xp - lo) / Double(max(1, hi - lo))
    }
}
