import SwiftUI
import MenaceCore

/// The score, today's ups and downs, recent history, and how points are earned and lost.
/// Opened from Settings and from the score on the home screen.
struct PointsView: View {
    @Environment(GameModel.self) private var model
    @State private var tab = 0

    private var book: PointsBook { model.state.points }
    private var today: String { model.game.days.dayKey(model.now) }
    private var gained: Int { book.day == today ? book.gainedToday : 0 }
    private var lost: Int { book.day == today ? book.lostToday : 0 }
    private var recent: [PointsEntry] { Array(book.history.reversed()) }
    private var gains: [PointReason] { PointReason.allCases.filter { !$0.isPenalty } }
    private var losses: [PointReason] { PointReason.allCases.filter(\.isPenalty) }

    /// Score on top, then History or Rules.
    var body: some View {
        Form {
            Section { header }
            Section {
                Picker("Show", selection: $tab) {
                    Text("History").tag(0)
                    Text("Rules").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if tab == 0 {
                Section("Today") { todayRow }
                Section("Recent") { historyRows(limit: 40) }
            } else {
                Section("How to earn") { ruleRows(gains) }
                Section {
                    ruleRows(losses)
                } header: {
                    Text("How to lose")
                } footer: {
                    footerNote
                }
            }
        }
        .navigationTitle("Points")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .onAppear { if UserDefaults.standard.integer(forKey: "LMPage") == 1 { tab = 1 } }
        #endif
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").foregroundStyle(Ink.iris)
                Text(book.total, format: .number).monospacedDigit()
            }
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            VStack(spacing: 6) {
                HStack {
                    Text("Level \(model.state.level)")
                    Spacer()
                    Text("\(model.state.pointsToNextLevel) to Level \(model.state.level + 1)").opacity(0.6)
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                ProgressView(value: levelProgress).tint(Ink.iris)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.total) points. Level \(model.state.level). \(model.state.pointsToNextLevel) more points to level \(model.state.level + 1).")
    }

    private var todayRow: some View {
        HStack {
            Label {
                Text(signedPoints(gained)).foregroundStyle(PointColor.gain)
            } icon: {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(PointColor.gain)
            }
            Spacer()
            Label {
                Text(lost == 0 ? "0" : signedPoints(-lost)).foregroundStyle(lost == 0 ? Color.secondary : PointColor.loss)
            } icon: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(PointColor.loss)
            }
        }
        .font(.system(.title3, design: .rounded).weight(.heavy))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: earned \(gained), lost \(lost)")
    }

    @ViewBuilder private func historyRows(limit: Int) -> some View {
        if recent.isEmpty {
            Text("Nothing yet. Go say hi.").foregroundStyle(.secondary)
        }
        ForEach(recent.prefix(limit)) { historyLine($0) }
    }

    private func historyLine(_ e: PointsEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.reason.symbol)
                .frame(width: 28)
                .foregroundStyle(e.amount < 0 ? PointColor.loss : Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.count > 1 ? "\(e.reason.label) ×\(e.count)" : e.reason.label)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(e.at.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signedPoints(e.amount))
                .font(.system(.body, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(e.amount < 0 ? PointColor.loss : PointColor.gain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.reason.label)\(e.count > 1 ? ", \(e.count) times" : ""), \(e.amount > 0 ? "plus" : "minus") \(abs(e.amount)) points")
    }

    @ViewBuilder private func ruleRows(_ reasons: [PointReason]) -> some View {
        ForEach(reasons, id: \.self) { ruleLine($0) }
    }

    private func ruleLine(_ r: PointReason) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: r.symbol)
                .frame(width: 28)
                .foregroundStyle(r.isPenalty ? PointColor.loss : Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.system(.body, design: .rounded).weight(.semibold))
                Text(r.rule).font(.subheadline).foregroundStyle(Color.primary.opacity(0.75))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footerNote: some View {
        Text("Points can go down, at most \(Tuning.maxPointsLostPerDay) a day. Your level never does.")
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(0.75))
    }

    private var levelProgress: Double {
        let s = model.state
        let lo = Tuning.xpForLevel(s.level), hi = Tuning.xpForLevel(s.level + 1)
        return min(1, max(0, Double(s.xp - lo) / Double(max(1, hi - lo))))
    }
}

/// The points page on its own, opened from the score on the home screen.
struct PointsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PointsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}
