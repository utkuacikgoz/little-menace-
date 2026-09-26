import SwiftUI
import MenaceCore

/// A card rendered from the player's actual the gremlin (theme, outfit, level, week, mood),
/// handed to the system share sheet. Nothing is posted automatically.
struct ShareCardView: View {
    let state: PetState
    let pose: GremlinPose

    var body: some View {
        let palette = ThemePalette.forID(state.wardrobe.theme)
        ZStack {
            palette.day
            RadialGradient(colors: [palette.glow.opacity(0.6), .clear], center: .init(x: 0.5, y: 0.45), startRadius: 10, endRadius: 260)
            VStack(spacing: 10) {
                Spacer(minLength: 12)
                GremlinView(pose: pose, hat: state.wardrobe.hat, neck: state.wardrobe.neck, size: 170, animated: false)
                Text(state.titleName)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                Text(Self.title(for: state.personality))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .opacity(0.85)
                // The score is the brag: same dark pill and gold star as the home scoreboard.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "star.fill").foregroundStyle(Ink.irisLight)
                    Text(state.points.total, format: .number).monospacedDigit()
                    Text("points").font(.system(size: 16, weight: .heavy, design: .rounded)).opacity(0.85)
                }
                .font(.system(size: 26, weight: .black, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Ink.body.opacity(0.85), in: Capsule())
                HStack(spacing: 18) {
                    Label("\(state.level)", systemImage: "arrow.up.circle.fill")
                    Label("\(state.stamps.days.count)/7", systemImage: "seal.fill")
                    Label("\(state.discoveries.count)", systemImage: "sparkles")
                }
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                Spacer(minLength: 6)
                Text("Little Menace")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .opacity(0.7)
                    .padding(.bottom, 14)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 360, height: 450)
    }

    static func title(for personality: Double) -> String {
        if personality > 0.3 { return "certified menace" }
        if personality < -0.3 { return "secret softie" }
        return "chaotic little gremlin"
    }
}

struct ShareCardSheet: View {
    @Environment(GameModel.self) private var model
    @State private var image: Image?

    var body: some View {
        VStack(spacing: 20) {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .accessibilityLabel("Share card of \(model.state.titleName), \(model.state.points.total) points, level \(model.state.level)")
                ShareLink(item: image, preview: SharePreview(model.state.titleName, image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Ink.body, in: Capsule())
                        .foregroundStyle(Ink.eye)
                }
            } else {
                ProgressView()
            }
        }
        .padding(24)
        .presentationDetents([.large])
        .presentationBackground(Ink.eye)
        .task { render() }
    }

    private func render() {
        var pose = model.pose
        if pose.sleeping == false { pose.look = .zero }
        let renderer = ImageRenderer(content: ShareCardView(state: model.state, pose: pose))
        renderer.scale = 3 // 1080 × 1350
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}
