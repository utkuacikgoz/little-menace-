import SwiftUI
import MenaceCore

enum HomeSheet: String, Identifiable {
    case wardrobe, stamps, share, settings, points
    #if DEBUG
    /// Screenshot tours only: the Midnight Snack page on its own.
    case collection
    #endif
    var id: String { rawValue }
}

/// The toy: one character, one bold background, three buttons. Everything else hides in a menu.
struct HomeView: View {
    @Environment(GameModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheet: HomeSheet?
    @State private var showPlay = false
    @State private var showMischief = false
    @GestureState private var stretch: CGSize = .zero
    /// Snack being dragged from the feed button, in the home coordinate space.
    @State private var snackAt: CGPoint?
    @State private var snackEaten = false

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let petSize = min(geo.size.width * 0.72, 300)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.46)
            let mouth = CGPoint(x: center.x, y: center.y + petSize * 0.08)

            ZStack {
                ThemeBackground(themeID: model.state.wardrobe.theme, dimmed: model.state.isAsleep)

                if model.state.isAsleep {
                    // Night while it naps: a darker sky with a moon.
                    Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Ink.irisLight)
                        .position(x: geo.size.width * 0.2, y: geo.size.height * 0.16)
                        .accessibilityHidden(true)
                }

                gremlin(size: petSize, center: center)

                if let bubble = model.bubble, !model.showNamePrompt, !model.showReminderOffer {
                    // Speech bubble above the head; below the gremlin while the mischief chip holds that spot.
                    SpeechBubble(text: bubble.text)
                        .accessibilityIdentifier("pet-dialogue")
                        .frame(maxWidth: geo.size.width - 64)
                        .position(x: center.x, y: model.pendingMischief == nil ? max(center.y - petSize * 0.72, Self.belowScore + 10) : min(center.y + petSize * 0.68, geo.size.height - 180))
                        .transition(.opacity)
                        .id(bubble.id)
                }

                if let prop = model.specialProp {
                    Image(systemName: prop)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .position(x: center.x - petSize * 0.55, y: center.y - petSize * 0.2)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }

                if let event = model.pendingMischief {
                    mischiefProp(event)
                        .position(x: center.x, y: max(center.y - petSize * 0.85, Self.belowScore))
                }

                if let snackAt {
                    CookieView(size: 44)
                        .scaleEffect(snackEaten ? 0.1 : 1)
                        .opacity(snackEaten ? 0 : 1)
                        .position(snackAt)
                        .allowsHitTesting(false)
                }

                VStack {
                    topBar
                    Spacer()
                    if model.showNamePrompt { NamePrompt() }
                    else if model.showReminderOffer { ReminderOffer() }
                    controls(mouth: mouth)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if let toast = model.toast {
                    ToastChip(toast: toast)
                        .position(x: geo.size.width / 2, y: 30)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .coordinateSpace(name: "home")
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.bubble)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.toast)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.showReminderOffer)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.showNamePrompt)
            .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
                if model.showHowToPlay {
                    CoachMarks(anchors: anchors)
                }
            }
            .onChange(of: sheet != nil || showMischief || model.activity != nil || model.showHowToPlay) { _, covered in
                model.homeObscured = covered
                if !covered { model.cancelSpecial() }
            }
            .onChange(of: model.activity) { _, _ in snackAt = nil }
            .onChange(of: sheet) { _, _ in snackAt = nil }
            .onChange(of: stretch) { _, value in
                // Gesture cancelled or released: eyes return to the player.
                if value == .zero { model.endAttention() }
            }
            .onChange(of: snackAt) { _, point in
                guard let point else { model.endAttention(); return }
                guard !snackEaten, !model.state.isAsleep else { return }
                let d = hypot(point.x - mouth.x, point.y - mouth.y)
                model.look = CGSize(width: max(-1, min(1, (point.x - mouth.x) / 120)), height: max(-1, min(1, (point.y - mouth.y) / 120)))
                if d < 160 && model.transient == nil { model.react(.attention, for: 0.6) }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .wardrobe: WardrobeView()
            case .stamps: StampCardView()
            case .share: ShareCardSheet()
            case .settings: SettingsView()
            case .points: PointsSheet()
            #if DEBUG
            case .collection: NavigationStack { CollectionView(collection: Catalog.collections[0]) }
            #endif
            }
        }
        .sheet(isPresented: $showMischief) {
            if let event = model.pendingMischief {
                MischiefSheet(event: event) { indulge in
                    showMischief = false
                    model.resolveMischief(event, indulge: indulge)
                }
                .presentationDetents([.height(300)])
            }
        }
        .fullScreenCover(item: $model.activity) { kind in
            ActivityContainer(kind: kind)
        }
        #if DEBUG
        .task {
            if let s = model.applyDebugLaunch() { sheet = s }
            switch UserDefaults.standard.string(forKey: "LMScreen") {
            case "playPicker": showPlay = true
            case "mischiefSheet": showMischief = true
            default: break
            }
        }
        #endif
    }

    // MARK: Gremlin

    private func gremlin(size: CGFloat, center: CGPoint) -> some View {
        let drag = DragGesture(minimumDistance: 6)
            .updating($stretch) { value, state, _ in
                state = Self.rubberBand(value.translation, limit: 70)
            }
            .onChanged { value in
                guard !model.state.isAsleep else { return }
                if model.transient != .attention { model.react(.attention, for: 10) }
                model.look = CGSize(width: max(-1, min(1, value.translation.width / 80)),
                                    height: max(-1, min(1, value.translation.height / 80)))
            }
            .onEnded { value in
                let pull = hypot(value.translation.width, value.translation.height)
                model.look = .zero
                if model.state.isAsleep {
                    model.react(.asleep, for: 0.1)
                } else {
                    model.react(pull > 60 ? .play : .touch, for: 1.1)
                    model.sounds.play(.boing)
                }
                model.haptics.play(.thud, intensity: min(1, pull / 120))
            }

        return GremlinView(pose: model.pose,
                         hat: model.state.wardrobe.hat,
                         neck: model.state.wardrobe.neck,
                         size: size,
                         stretch: stretch)
            .contentShape(Rectangle())
            .onTapGesture { model.pet() }
            .onLongPressGesture(minimumDuration: 0.5) { model.longPress() }
            .gesture(drag)
            .coachTarget(.pet)
            .position(center)
            .accessibilityElement()
            .accessibilityLabel(model.state.titleName)
            .accessibilityIdentifier("pet")
            .accessibilityValue(spokenState)
            .accessibilityHint("Double tap to pet.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.pet() }
            .accessibilityAction(named: "Feed") { _ = model.feed() }
            .accessibilityAction(named: model.state.isAsleep ? "Wake" : "Nap") { model.toggleSleep() }
            .accessibilityAction(named: "Tickle") { model.longPress() }
    }

    private var spokenState: String {
        let s = model.state
        if s.isAsleep { return "Asleep" }
        var parts: [String] = []
        parts.append(s.needs.fullness < 35 ? "Hungry" : s.needs.fullness > 85 ? "Full" : "Not hungry")
        parts.append(s.needs.energy < 30 ? "Sleepy" : "Awake")
        parts.append(s.needs.joy < 40 ? "Bored" : "Cheerful")
        if s.personality > 0.4 { parts.append("Feeling menacing") }
        if s.personality < -0.4 { parts.append("Feeling sweet") }
        parts.append("Level \(s.level)")
        return parts.joined(separator: ", ")
    }

    /// Centre line for things placed under the scoreboard at the top.
    static let belowScore: CGFloat = 116

    static func rubberBand(_ t: CGSize, limit: CGFloat) -> CGSize {
        func band(_ v: CGFloat) -> CGFloat {
            let sign: CGFloat = v < 0 ? -1 : 1
            return sign * limit * (1 - exp(-abs(v) / limit))
        }
        return CGSize(width: band(t.width), height: band(t.height))
    }

    // MARK: Chrome

    private var topBar: some View {
        ZStack(alignment: .top) {
            PointsBadge { sheet = .points }.coachTarget(.points)
            HStack {
                Spacer()
                menu
            }
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.pointsDelta)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.state.points.total)
    }

    private var menu: some View {
        Menu {
            Button { sheet = .wardrobe } label: { Label("Wardrobe", systemImage: "tshirt") }
            Button { sheet = .stamps } label: { Label("Stamps", systemImage: "seal") }
            Button { sheet = .share } label: { Label("Share", systemImage: "square.and.arrow.up") }
            Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title2.weight(.heavy))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge) // stays inside its circle
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.18), in: Circle())
        }
        .accessibilityLabel("More")
    }

    private func controls(mouth: CGPoint) -> some View {
        let needs = model.state.needs
        return ZStack(alignment: .bottom) {
            if showPlay {
                PlayPicker { kind in
                    showPlay = false
                    model.startActivity(kind)
                }
                .offset(y: -84)
                .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 28) {
                feedButton(fullness: needs.fullness / 100, mouth: mouth)
                RingButton(ring: needs.joy / 100, label: "Play", caption: needCaption(.joy, needs.joy), action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showPlay.toggle() }
                    model.haptics.play(.tap)
                }) {
                    Image(systemName: showPlay ? "xmark" : "tennisball.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .coachTarget(.play)
                RingButton(ring: needs.energy / 100, label: model.state.isAsleep ? "Wake" : "Nap",
                           caption: needCaption(.energy, needs.energy), action: {
                    showPlay = false
                    model.toggleSleep()
                }) {
                    Image(systemName: model.state.isAsleep ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .coachTarget(.nap)
            }
        }
    }

    private enum Need { case fullness, joy, energy }

    /// Needs read as what the gremlin lacks: Hungry / Bored / Sleepy, counting up.
    private func needCaption(_ need: Need, _ value: Double) -> String {
        let lack = "\(Int(max(0, min(100, 100 - value)).rounded()))%"
        switch need {
        case .fullness: return "Hungry \(lack)"
        case .joy: return "Bored \(lack)"
        case .energy: return "Sleepy \(lack)"
        }
    }

    /// Tap: The gremlin gets a snack tossed in. Drag: carry the snack to the gremlin's mouth yourself.
    private func feedButton(fullness: Double, mouth: CGPoint) -> some View {
        let drag = DragGesture(minimumDistance: 4, coordinateSpace: .named("home"))
            .onChanged { v in
                snackEaten = false
                snackAt = v.location
            }
            .onEnded { v in
                let close = hypot(v.location.x - mouth.x, v.location.y - mouth.y) < 80
                deliverSnack(from: v.location, to: mouth, dropped: !close)
            }
        return RingButton(ring: fullness, label: "Feed", caption: needCaption(.fullness, fullness * 100), action: {
            showPlay = false
            model.feed()
        }) {
            CookieView(size: 34)
        }
        .simultaneousGesture(drag)
        .coachTarget(.feed)
    }

    private func deliverSnack(from: CGPoint, to mouth: CGPoint, dropped: Bool) {
        if dropped {
            withAnimation(.easeIn(duration: 0.25)) { snackEaten = true }
            clearSnack(after: 0.3)
            return
        }
        let ate = model.feed()
        if ate {
            withAnimation(.easeIn(duration: 0.15)) { snackAt = mouth; snackEaten = true }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { snackAt = CGPoint(x: from.x, y: from.y + 140); snackEaten = true }
        }
        clearSnack(after: 0.35)
    }

    private func clearSnack(after seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            snackAt = nil
            snackEaten = false
        }
    }

    private func mischiefProp(_ event: MischiefEvent) -> some View {
        Button { showMischief = true } label: {
            // A chip above the gremlin that says what's going on.
            HStack(spacing: 8) {
                Image(systemName: event.prop)
                Text("Up to something…")
            }
            .font(.system(.headline, design: .rounded).weight(.heavy))
            .foregroundStyle(Ink.body)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Ink.eye, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .buttonStyle(SquishButtonStyle())
        .phaseAnimator(reduceMotion ? [0.0] : [0.0, -8.0]) { view, y in
            view.offset(y: y)
        } animation: { _ in .easeInOut(duration: 0.8) }
        .accessibilityLabel("\(model.state.titleName) is up to something")
    }
}

private struct PlayPicker: View {
    var pick: (ActivityKind) -> Void

    var body: some View {
        HStack(spacing: 18) { options }
            .padding(10)
            .background(.white.opacity(0.22), in: Capsule())
    }

    @ViewBuilder private var options: some View {
        option(.snackToss, "Snack toss", short: "Snack") { CookieView(size: 30) }
        option(.sockTug, "Sock tug", short: "Tug") {
            SockView(style: "stripe").scaleEffect(0.3).frame(width: 34, height: 40)
        }
        option(.cushionHunt, "Cushion hunt", short: "Hunt") {
            CushionView().scaleEffect(0.38).frame(width: 40, height: 30)
        }
    }

    private func option<Icon: View>(_ kind: ActivityKind, _ label: String, short: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button { pick(kind) } label: {
            VStack(spacing: 4) {
                icon()
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.25), in: Circle())
                Text(short)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(Ink.body)
            }
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(label)
    }
}

/// One line, one field: shown once after the first pet. Skipping keeps "your gremlin";
/// a name can be given later in Settings.
private struct NamePrompt: View {
    @Environment(GameModel.self) private var model
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name me?", text: $name)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Ink.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { model.rename(name) }
                .onChange(of: name) { _, new in
                    if new.count > PetState.maxNameLength { name = String(new.prefix(PetState.maxNameLength)) }
                }
                .accessibilityLabel("Name")
            Button { model.rename(name) } label: {
                Image(systemName: "checkmark").font(.headline.weight(.heavy))
                    .frame(width: 40, height: 40).background(Ink.body, in: Circle()).foregroundStyle(Ink.eye)
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Save name")
            Button { model.rename("") } label: {
                Image(systemName: "xmark").font(.headline.weight(.heavy))
                    .frame(width: 40, height: 40).background(Ink.body.opacity(0.12), in: Circle()).foregroundStyle(Ink.body)
            }
            .accessibilityLabel("Not now")
        }
        .padding(12)
        .background(Ink.eye, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.bottom, 12)
        .environment(\.colorScheme, .light) // cream card: keep the placeholder and caret dark in Dark Mode
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ReminderOffer: View {
    @Environment(GameModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill").font(.title2)
                Text("Nudge me later?")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
            }
            HStack(spacing: 10) {
                Button(action: accept) {
                    Text("Yes, nudge me").font(.system(.headline, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Ink.body, in: Capsule()).foregroundStyle(Ink.eye)
                }
                Button { model.dismissReminderOffer() } label: {
                    Text("No thanks").font(.system(.headline, design: .rounded).weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Ink.body.opacity(0.12), in: Capsule()).foregroundStyle(Ink.body)
                }
            }
        }
        .foregroundStyle(Ink.body)
        .padding(16)
        .background(Ink.eye, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.bottom, 12)
        .environment(\.colorScheme, .light) // cream card: keep the placeholder and caret dark in Dark Mode
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func accept() {
        model.dismissReminderOffer()
        Task { await model.setReminders(true) }
    }
}
