import AVKit
import SwiftUI

// MARK: - Native AirPlay Picker Button (AVRoutePickerView)
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(red: 0.29, green: 0.35, blue: 0.44, alpha: 1)
        picker.activeTintColor = UIColor(red: 0.29, green: 0.83, blue: 0.78, alpha: 1)
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - 1. Home Screen (1:1 Mockup + Smooth 1P/2P Slide + Rising Soap Bubbles)
struct HomeScreenView: View {
    @ObservedObject var settings: AppSettings
    let onStart: () -> Void
    let onOpenSettings: () -> Void

    @State private var floatUp = false
    @State private var momoBounce = false
    @State private var popoBounce = false

    var body: some View {
        ZStack {
            // Cream-to-sky pastel background matching mockup_01_home
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.89),
                    Color(red: 1.0, green: 0.98, blue: 0.95),
                    Color(red: 0.82, green: 0.94, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft rising soap bubbles
            RisingBubblesView()

            VStack(spacing: 0) {
                // Top-right AirPlay & Settings glass buttons
                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        AirPlayButton()
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))

                        Button(action: {
                            SoundEngine.shared.playClick()
                            onOpenSettings()
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color(red: 0.29, green: 0.35, blue: 0.44))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                // HD 3D Puffy Logo
                BundleImage.swiftUIImage(named: "logo_pangpang")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 86)
                    .shadow(color: .brown.opacity(0.14), radius: 8, y: 4)
                    .offset(y: floatUp ? -4 : 0)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floatUp)

                // Characters stage with silky 1P <-> 2P glide
                ZStack(alignment: .bottom) {
                    // Momo (P1)
                    BundleImage.swiftUIImage(named: "momo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: settings.players == 1 ? 205 : 190)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                        .offset(
                            x: settings.players == 1 ? 0 : -135,
                            y: (floatUp ? -5 : 0) + (momoBounce ? -14 : 0)
                        )
                        .animation(.easeOut(duration: 0.5), value: settings.players)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: floatUp)
                        .onTapGesture {
                            SoundEngine.shared.playPop(combo: 1)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { momoBounce = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                withAnimation(.spring()) { momoBounce = false }
                            }
                        }

                    // Popo (P2)
                    BundleImage.swiftUIImage(named: "popo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 178)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                        .offset(
                            x: settings.players == 1 ? 190 : 135,
                            y: (floatUp ? 0 : -5) + (popoBounce ? -14 : 0)
                        )
                        .opacity(settings.players == 1 ? 0 : 1)
                        .scaleEffect(settings.players == 1 ? 0.85 : 1)
                        .animation(.easeOut(duration: 0.45), value: settings.players)
                        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: floatUp)
                        .onTapGesture {
                            SoundEngine.shared.playPop(combo: 3)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { popoBounce = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                withAnimation(.spring()) { popoBounce = false }
                            }
                        }

                    // Centered Floating 1P/2P Toggle & Clean Yellow Start Button
                    VStack(spacing: 10) {
                        PlayerSegmentPill(players: $settings.players)

                        Button(action: {
                            SoundEngine.shared.playClick()
                            onStart()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .black))
                                Text("시작!")
                                    .font(AppFont.swiftUIFont(size: 25))
                            }
                            .foregroundStyle(.white)
                            .shadow(color: Color(red: 0.725, green: 0.431, blue: 0.0).opacity(0.34), radius: 2, y: 1)
                            .frame(minWidth: 186, minHeight: 50)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.886, blue: 0.290),
                                        Color(red: 1.0, green: 0.761, blue: 0.039),
                                        Color(red: 0.961, green: 0.686, blue: 0.0),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
                            .shadow(color: Color(red: 0.949, green: 0.678, blue: 0.0).opacity(0.38), radius: 12, y: 5)
                        }
                    }
                    .offset(y: 12)
                }
                .frame(height: 215)

                Spacer(minLength: 18)
            }
        }
        .onAppear { floatUp = true }
    }
}

struct RisingBubblesView: View {
    @State private var animate = false
    private let specs: [(CGFloat, CGFloat, Double)] = [
        (52, 0.16, 12), (28, 0.80, 10), (38, 0.26, 13), (22, 0.72, 9), (44, 0.86, 14),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<specs.count, id: \.self) { i in
                let (sz, xFrac, dur) = specs[i]
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.85), Color.cyan.opacity(0.18), Color.pink.opacity(0.15)],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: sz
                        )
                    )
                    .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1.2))
                    .frame(width: sz, height: sz)
                    .position(x: geo.size.width * xFrac, y: animate ? -sz : geo.size.height + sz)
                    .animation(.linear(duration: dur).repeatForever(autoreverses: false).delay(Double(i) * 1.6), value: animate)
            }
        }
        .allowsHitTesting(false)
        .onAppear { animate = true }
    }
}

// MARK: - Global Hand-Target Coordinate Preference (Enables Single-Hand Air Cursor across ALL buttons & modals!)
struct HandTargetBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func handTarget(_ id: String, hovered: String?) -> some View {
        let isHovered = (hovered == id)
        return self
            .scaleEffect(isHovered ? 1.09 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(red: 0.13, green: 1.0, blue: 0.53), lineWidth: isHovered ? 4 : 0)
                    .shadow(color: isHovered ? Color.green.opacity(0.6) : .clear, radius: 10)
            )
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HandTargetBoundsKey.self, value: [id: g.frame(in: .named("appRoot"))])
                }
            )
    }
}

struct PlayerSegmentPill: View {
    @Binding var players: Int
    var prefix: String = ""
    var hoveredTarget: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                SoundEngine.shared.playClick()
                withAnimation(.easeOut(duration: 0.25)) { players = 1 }
            }) {
                HStack(spacing: 4) {
                    BundleImage.swiftUIImage(named: "momo_head")
                        .resizable().scaledToFit().frame(width: 18, height: 18)
                    Text("1인")
                }
                .font(AppFont.swiftUIFont(size: 16))
                .foregroundStyle(players == 1 ? .white : Color(red: 0.36, green: 0.41, blue: 0.49))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    players == 1
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.31, green: 0.84, blue: 0.79), Color(red: 0.23, green: 0.75, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.clear),
                    in: Capsule()
                )
            }
            .handTarget(prefix.isEmpty ? "pill_1p" : "\(prefix)_1p", hovered: hoveredTarget)

            Button(action: {
                SoundEngine.shared.playClick()
                withAnimation(.easeOut(duration: 0.25)) { players = 2 }
            }) {
                HStack(spacing: 4) {
                    HStack(spacing: -5) {
                        BundleImage.swiftUIImage(named: "momo_head").resizable().scaledToFit().frame(width: 18, height: 18)
                        BundleImage.swiftUIImage(named: "popo_head").resizable().scaledToFit().frame(width: 18, height: 18)
                    }
                    Text("2인")
                }
                .font(AppFont.swiftUIFont(size: 16))
                .foregroundStyle(players == 2 ? .white : Color(red: 0.36, green: 0.41, blue: 0.49))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    players == 2
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.31, green: 0.84, blue: 0.79), Color(red: 0.23, green: 0.75, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.clear),
                    in: Capsule()
                )
            }
            .handTarget(prefix.isEmpty ? "pill_2p" : "\(prefix)_2p", hovered: hoveredTarget)
        }
        .padding(4)
        .background(.white.opacity(0.95), in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }
}

// MARK: - Stage Select Local Target Bounds (Exact card & arrow geometry for 1:1 Air Cursor hit-testing!)
private struct SelectTargetBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - 2. Stage Select Screen (7-Game Horizontal 4-Card Carousel + Live Camera + Air Cursor!)
struct StageSelectView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var camera: VisionCameraManager
    var hoveredGlobalTarget: String? = nil
    var modalActive: Bool = false
    let onBack: () -> Void
    let onSelectGame: (GameType) -> Void
    let onOpenSettings: () -> Void

    private let allGames = GameType.allCases
    private let visibleCount = 4
    private var maxOffset: Int { max(0, allGames.count - visibleCount) }

    @State private var floatCard = false
    @State private var featured: GameType = .fruit
    @State private var carouselOffset: Int = 0
    @State private var hoveredGame: GameType? = nil
    @State private var hoveredArrow: Int = 0 // -1 = left (<), 1 = right (>), 0 = none
    @State private var dwellProgress: CGFloat = 0
    @State private var dwellTickStep = 0
    @State private var arrowCooldown: CGFloat = 0
    @State private var entryCooldown: CGFloat = 0.75
    @State private var selectBounds: [String: CGRect] = [:]
    @State private var selectSize: CGSize = CGSize(width: 852, height: 393)
    @State private var airTimer: Timer?

    private var visibleGames: [GameType] {
        let start = max(0, min(maxOffset, carouselOffset))
        let end = min(allGames.count, start + visibleCount)
        return Array(allGames[start..<end])
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                if camera.isUsingCamera && !settings.devMode {
                    CameraPreviewView(manager: camera)
                        .ignoresSafeArea()
                    // Light tint opacity 0.22 so the child clearly sees themselves behind floating cards!
                    Color(red: 0.06, green: 0.10, blue: 0.18)
                        .opacity(0.22)
                        .ignoresSafeArea()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.78, green: 0.92, blue: 1.0), Color(red: 1.0, green: 0.98, blue: 0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }

                VStack(spacing: 8) {
                    // Header bar (all buttons support Single-Hand Air Cursor + instant touch!)
                    HStack {
                        Button(action: { SoundEngine.shared.playClick(); onBack() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.95), in: Circle())
                                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                        }
                        .handTarget("select_back", hovered: hoveredGlobalTarget)

                        Spacer()
                        Text("놀이 고르기")
                            .font(AppFont.swiftUIFont(size: 27))
                            .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.90), in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        Spacer()

                        HStack(spacing: 10) {
                            PlayerSegmentPill(players: $settings.players, prefix: "select", hoveredTarget: hoveredGlobalTarget)
                            Button(action: { SoundEngine.shared.playClick(); onOpenSettings() }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color(red: 0.29, green: 0.35, blue: 0.44))
                                    .frame(width: 44, height: 44)
                                    .background(.white.opacity(0.95), in: Circle())
                                    .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                            }
                            .handTarget("select_settings", hovered: hoveredGlobalTarget)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer(minLength: 0)

                    // Horizontal 4-Card Carousel with Chunky < > Arrows
                    HStack(spacing: 10) {
                        // Left Arrow (<)
                        carouselArrowButton(direction: -1, enabled: carouselOffset > 0)

                        // 4 Visible Cards
                        HStack(spacing: 12) {
                            ForEach(visibleGames) { game in
                                let isAirHover = hoveredGame == game
                                let isFeat = featured == game || isAirHover
                                let lvl = game.intensityLevel(quietMode: settings.quietMode)
                                Button(action: {
                                    SoundEngine.shared.playClick()
                                    featured = game
                                    onSelectGame(game)
                                }) {
                                    VStack(spacing: 7) {
                                        BundleImage.swiftUIImage(named: game.cardImageName)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 106)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                        Text(game.title)
                                            .font(AppFont.swiftUIFont(size: 18))
                                            .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.72)

                                        HStack(spacing: 3) {
                                            ForEach(0..<lvl, id: \.self) { _ in
                                                Image(systemName: "flame.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(lvl == 1 ? .green : lvl == 2 ? .orange : .red)
                                            }
                                            Text(game.intensityLabel(quietMode: settings.quietMode))
                                                .font(AppFont.swiftUIFont(size: 13))
                                                .foregroundStyle(lvl == 1 ? Color(red: 0.17, green: 0.54, blue: 0.34) : lvl == 2 ? Color(red: 0.79, green: 0.41, blue: 0.07) : Color(red: 0.84, green: 0.24, blue: 0.29))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            (lvl == 1 ? Color.green : lvl == 2 ? Color.orange : Color.red).opacity(0.13),
                                            in: Capsule()
                                        )

                                        // 1.5초 드웰 프로그레스 바 (공중 원핸드 호버 시 차오름!)
                                        GeometryReader { bGeo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.black.opacity(0.08))
                                                Capsule()
                                                    .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.90, blue: 0.52), Color(red: 1.0, green: 0.84, blue: 0.20)], startPoint: .leading, endPoint: .trailing))
                                                    .frame(width: isAirHover ? bGeo.size.width * dwellProgress : 0)
                                            }
                                        }
                                        .frame(height: 7)
                                        .opacity(isAirHover ? 1 : 0)
                                    }
                                    .padding(9)
                                    .frame(maxWidth: 180)
                                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(isFeat ? Color(red: 1.0, green: 0.85, blue: 0.30) : .white, lineWidth: isAirHover ? 5 : 3.5)
                                    )
                                    .shadow(color: isFeat ? Color.yellow.opacity(0.40) : .black.opacity(0.16), radius: 14, y: 6)
                                    .scaleEffect(isAirHover ? 1.06 : 1.0)
                                    .offset(y: floatCard ? -4 : 0)
                                    .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isAirHover)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    GeometryReader { g in
                                        Color.clear.preference(
                                            key: SelectTargetBoundsKey.self,
                                            value: ["card_\(game.rawValue)": g.frame(in: .named("selectRoot"))]
                                        )
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                                    removal: .opacity.combined(with: .scale(scale: 0.94))
                                ))
                            }
                        }
                        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: carouselOffset)
                        .gesture(
                            DragGesture(minimumDistance: 28)
                                .onEnded { val in
                                    if val.translation.width < -32 && carouselOffset < maxOffset {
                                        slideCarousel(by: 1)
                                    } else if val.translation.width > 32 && carouselOffset > 0 {
                                        slideCarousel(by: -1)
                                    }
                                }
                        )

                        // Right Arrow (>)
                        carouselArrowButton(direction: 1, enabled: carouselOffset < maxOffset)
                    }
                    .padding(.horizontal, 12)

                    // Pagination Dots (offsets 0...maxOffset)
                    HStack(spacing: 8) {
                        ForEach(0...maxOffset, id: \.self) { page in
                            Button(action: {
                                SoundEngine.shared.playClick()
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                    carouselOffset = page
                                    hoveredGame = nil
                                    dwellProgress = 0
                                }
                            }) {
                                Capsule()
                                    .fill(carouselOffset == page ? Color(red: 1.0, green: 0.85, blue: 0.25) : Color.white.opacity(0.72))
                                    .frame(width: carouselOffset == page ? 26 : 10, height: 10)
                                    .overlay(
                                        Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.22), in: Capsule())

                    Spacer(minLength: 0)

                    Text("✋ 한 손을 카드에 1.5초 올리거나 ◀ ▶ 에 0.8초 올려 넘겨요! · \(settings.quietMode ? "🪶 층간소음 모드 ON" : "🔥 활기찬 모드")")
                        .font(AppFont.swiftUIFont(size: 13.5))
                        .foregroundStyle(Color(red: 0.14, green: 0.26, blue: 0.30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.86), in: Capsule())
                        .padding(.bottom, 6)
                }

                // Bottom-right peeking mascots
                HStack(spacing: -14) {
                    BundleImage.swiftUIImage(named: "momo_head").resizable().scaledToFit().frame(width: 56)
                    BundleImage.swiftUIImage(named: "popo_head").resizable().scaledToFit().frame(width: 60)
                }
                .padding(.trailing, 12)
                .offset(y: 10)
                .allowsHitTesting(false)

                // Single Dominant Hand Air Cursor + Dwell Ring Overlay (hidden when modal or top-bar global cursor is active)
                if camera.airCursor.active && camera.isUsingCamera && !settings.devMode && !modalActive && hoveredGlobalTarget == nil {
                    ZStack {
                        Circle()
                            .fill((hoveredArrow != 0 ? Color.yellow : Color.green).opacity(0.24))
                            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 4))
                            .frame(width: 64, height: 64)
                        Circle()
                            .trim(from: 0, to: dwellProgress)
                            .stroke(
                                hoveredArrow != 0 ? Color(red: 1.0, green: 0.84, blue: 0.20) : Color(red: 0.13, green: 1.0, blue: 0.53),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 64, height: 64)
                        Text(hoveredArrow == -1 ? "◀" : (hoveredArrow == 1 ? "▶" : "✋"))
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: (hoveredArrow != 0 ? Color.yellow : Color.green).opacity(0.65), radius: 12)
                    .position(x: camera.airCursor.x * geo.size.width, y: camera.airCursor.y * geo.size.height)
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "selectRoot")
            .onPreferenceChange(SelectTargetBoundsKey.self) { bounds in
                selectBounds = bounds
            }
            .onAppear {
                floatCard = true
                selectSize = geo.size
                entryCooldown = 0.75
                camera.updateViewSize(geo.size)
                if !settings.devMode {
                    camera.start(expectedPlayers: settings.players, devMode: false)
                }
                startAirCursorLoop()
            }
            .onChange(of: geo.size) { _, newSize in
                selectSize = newSize
                camera.updateViewSize(newSize)
            }
            .onChange(of: modalActive) { _, isActive in
                if !isActive {
                    entryCooldown = 0.75
                    dwellProgress = 0
                    hoveredGame = nil
                    hoveredArrow = 0
                }
            }
            .onChange(of: settings.devMode) { _, isDev in
                if isDev {
                    camera.stopCamera()
                    camera.start(expectedPlayers: settings.players, devMode: true)
                } else {
                    camera.start(expectedPlayers: settings.players, devMode: false)
                }
            }
            .onDisappear {
                airTimer?.invalidate()
                airTimer = nil
            }
        }
    }

    @ViewBuilder
    private func carouselArrowButton(direction: Int, enabled: Bool) -> some View {
        let isHovered = (hoveredArrow == direction) && enabled
        Button(action: {
            if enabled { slideCarousel(by: direction) }
        }) {
            ZStack {
                Circle()
                    .fill(enabled ? Color.white.opacity(0.95) : Color.white.opacity(0.45))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle().stroke(isHovered ? Color(red: 1.0, green: 0.84, blue: 0.20) : Color.white, lineWidth: isHovered ? 4 : 2.5)
                    )
                    .shadow(color: isHovered ? Color.yellow.opacity(0.55) : .black.opacity(0.16), radius: 10, y: 4)

                if isHovered {
                    Circle()
                        .trim(from: 0, to: dwellProgress)
                        .stroke(Color(red: 0.13, green: 1.0, blue: 0.53), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 58, height: 58)
                }

                Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(enabled ? Color(red: 0.16, green: 0.22, blue: 0.30) : Color.gray.opacity(0.45))
            }
            .scaleEffect(isHovered ? 1.14 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .background(
            GeometryReader { g in
                Color.clear.preference(
                    key: SelectTargetBoundsKey.self,
                    value: [direction < 0 ? "arrow_prev" : "arrow_next": g.frame(in: .named("selectRoot"))]
                )
            }
        )
    }

    private func slideCarousel(by delta: Int) {
        let next = max(0, min(maxOffset, carouselOffset + delta))
        guard next != carouselOffset else { return }
        SoundEngine.shared.playClick()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            carouselOffset = next
            hoveredGame = nil
            dwellProgress = 0
            dwellTickStep = 0
        }
    }

    private func findNearestSelectTarget(pt: CGPoint, ids: [String], pad: CGFloat, currentId: String?) -> String? {
        var bestId: String? = nil
        var bestScore: CGFloat = .infinity
        for id in ids {
            guard let rect = selectBounds[id], rect.width >= 4, rect.height >= 4 else { continue }
            let insideExact = rect.contains(pt)
            let insidePad = rect.insetBy(dx: -pad, dy: -pad).contains(pt)
            guard insidePad else { continue }
            let nearX = max(rect.minX, min(pt.x, rect.maxX))
            let nearY = max(rect.minY, min(pt.y, rect.maxY))
            let edgeDist = hypot(pt.x - nearX, pt.y - nearY)
            let centerDist = hypot(pt.x - rect.midX, pt.y - rect.midY)
            let stickyBonus: CGFloat = (id == currentId) ? -10 : 0
            let score = (insideExact ? 0 : 1000) + edgeDist * 10 + centerDist * 0.08 + stickyBonus
            if score < bestScore {
                bestScore = score
                bestId = id
            }
        }
        return bestId
    }

    private func startAirCursorLoop() {
        airTimer?.invalidate()
        airTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            if arrowCooldown > 0 { arrowCooldown = max(0, arrowCooldown - 0.04) }
            if entryCooldown > 0 { entryCooldown = max(0, entryCooldown - 0.04) }

            guard camera.airCursor.active, camera.isUsingCamera, !settings.devMode, !modalActive, hoveredGlobalTarget == nil else {
                dwellProgress = max(0, dwellProgress - 0.08)
                if dwellProgress <= 0 {
                    hoveredGame = nil
                    hoveredArrow = 0
                    dwellTickStep = 0
                }
                return
            }

            let pt = CGPoint(x: camera.airCursor.x * selectSize.width, y: camera.airCursor.y * selectSize.height)

            // 1) Check exact carousel arrow rects first (0.8s dwell with cooldown!)
            var arrowIds: [String] = []
            if carouselOffset > 0 { arrowIds.append("arrow_prev") }
            if carouselOffset < maxOffset { arrowIds.append("arrow_next") }
            let curArrowId = hoveredArrow == -1 ? "arrow_prev" : (hoveredArrow == 1 ? "arrow_next" : nil)

            if let hitArrow = findNearestSelectTarget(pt: pt, ids: arrowIds, pad: 20, currentId: curArrowId) {
                let dir = (hitArrow == "arrow_prev") ? -1 : 1
                hoveredGame = nil
                if hoveredArrow != dir {
                    hoveredArrow = dir
                    dwellProgress = 0
                    dwellTickStep = 0
                }
                if arrowCooldown <= 0 && entryCooldown <= 0 {
                    dwellProgress = min(1.0, dwellProgress + 0.04 / 0.8)
                    if dwellProgress >= 1.0 {
                        dwellProgress = 0
                        hoveredArrow = 0
                        arrowCooldown = 0.72
                        slideCarousel(by: dir)
                    }
                }
                return
            }

            // 2) Check exact visible card rects (nearest match, 1.5s dwell!)
            hoveredArrow = 0
            let vis = visibleGames
            let cardIds = vis.map { "card_\($0.rawValue)" }
            let curCardId = hoveredGame.map { "card_\($0.rawValue)" }

            if let hitCardId = findNearestSelectTarget(pt: pt, ids: cardIds, pad: 10, currentId: curCardId),
               let target = vis.first(where: { "card_\($0.rawValue)" == hitCardId }) {
                if hoveredGame != target {
                    hoveredGame = target
                    dwellProgress = 0
                    dwellTickStep = 0
                }
                if entryCooldown <= 0 {
                    dwellProgress = min(1.0, dwellProgress + 0.04 / 1.5)
                    let step = Int(dwellProgress * 3)
                    if step > dwellTickStep && step < 3 {
                        dwellTickStep = step
                        SoundEngine.shared.playClick()
                    }
                    if dwellProgress >= 1.0 {
                        dwellProgress = 0
                        dwellTickStep = 0
                        airTimer?.invalidate()
                        SoundEngine.shared.playReadyOk()
                        featured = target
                        onSelectGame(target)
                    }
                }
            } else {
                dwellProgress = max(0, dwellProgress - 0.07)
                if dwellProgress <= 0 {
                    hoveredGame = nil
                    dwellTickStep = 0
                }
            }
        }
    }
}

// MARK: - 5. Minimal Parent Settings Modal (1:1 Mockup + Full Hand & Touch Support!)
struct SettingsModalView: View {
    @ObservedObject var settings: AppSettings
    var hoveredGlobalTarget: String? = nil
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea()
                .onTapGesture { SoundEngine.shared.playClick(); onClose() }

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    HStack {
                        Color.clear.frame(width: 38, height: 38)
                        Spacer()
                        Text("설정")
                            .font(AppFont.swiftUIFont(size: 25))
                            .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                        Spacer()
                        Button(action: { SoundEngine.shared.playClick(); onClose() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(.gray)
                                .frame(width: 38, height: 38)
                                .background(Color(white: 0.93), in: Circle())
                        }
                        .handTarget("set_close", hovered: hoveredGlobalTarget)
                    }
                    .padding(.bottom, 10)

                    // Row 1: Players (Hand + Touch)
                    settingRow(icon: "person.2.fill", title: "플레이 인원") {
                        HStack(spacing: 6) {
                            pillOpt("1인", active: settings.players == 1, id: "set_1p") { settings.players = 1 }
                            pillOpt("2인", active: settings.players == 2, id: "set_2p") { settings.players = 2 }
                        }
                    }
                    Divider()

                    // Row 2: Quiet Mode (Hand + Touch)
                    settingRow(icon: "leaf.fill", title: "층간소음 모드") {
                        togglePill(isOn: settings.quietMode, id: "set_quiet") { settings.quietMode.toggle() }
                    }
                    Divider()

                    // Row 3: Play Speed (Hand + Touch)
                    settingRow(icon: "gauge.medium", title: "놀이 속도") {
                        HStack(spacing: 5) {
                            ForEach(PlaySpeed.allCases, id: \.rawValue) { sp in
                                pillOpt(sp.label, active: settings.speedRaw == sp.rawValue, id: "set_\(sp.rawValue)") {
                                    settings.speedRaw = sp.rawValue
                                }
                            }
                        }
                    }
                    Divider()

                    // Row 4: Sound & AirPlay TV (Hand -/+ + Touch Slider)
                    settingRow(icon: "speaker.wave.2.fill", title: "소리 · TV 연결") {
                        HStack(spacing: 8) {
                            Button(action: {
                                settings.volume = max(0, settings.volume - 0.2)
                                SoundEngine.shared.volume = Float(settings.volume)
                                SoundEngine.shared.playClick()
                            }) {
                                Text("−")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(Color(red: 0.2, green: 0.26, blue: 0.35))
                                    .frame(width: 34, height: 34)
                                    .background(Color(white: 0.94), in: Circle())
                            }
                            .handTarget("set_vol_down", hovered: hoveredGlobalTarget)

                            Text("\(Int(round(settings.volume * 100)))%")
                                .font(AppFont.swiftUIFont(size: 15.5))
                                .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                                .frame(width: 44)

                            Button(action: {
                                settings.volume = min(1, settings.volume + 0.2)
                                SoundEngine.shared.volume = Float(settings.volume)
                                SoundEngine.shared.playClick()
                            }) {
                                Text("+")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(Color(red: 0.2, green: 0.26, blue: 0.35))
                                    .frame(width: 34, height: 34)
                                    .background(Color(white: 0.94), in: Circle())
                            }
                            .handTarget("set_vol_up", hovered: hoveredGlobalTarget)

                            HStack(spacing: 4) {
                                AirPlayButton().frame(width: 24, height: 24)
                                Text("TV")
                                    .font(AppFont.swiftUIFont(size: 13.5))
                                    .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.95), in: Capsule())
                        }
                    }
                    Divider()

                    // Row 5: Developer Mode (Hand + Touch)
                    settingRow(icon: "hammer.fill", title: "개발자 모드 (터치 테스트)") {
                        togglePill(isOn: settings.devMode, id: "set_dev") { settings.devMode.toggle() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 540)
                .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 24, y: 10)

                // Peeking 3D mascots at bottom-right
                HStack(spacing: -12) {
                    BundleImage.swiftUIImage(named: "momo_head").resizable().scaledToFit().frame(width: 56)
                    BundleImage.swiftUIImage(named: "popo_head").resizable().scaledToFit().frame(width: 60)
                }
                .offset(x: 10, y: 18)
                .allowsHitTesting(false)
            }
        }
    }

    private func pillOpt(_ title: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: { SoundEngine.shared.playClick(); action() }) {
            Text(title)
                .font(AppFont.swiftUIFont(size: 14.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(active ? .white : Color(red: 0.35, green: 0.42, blue: 0.52))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(active ? Color(red: 0.26, green: 0.77, blue: 0.86) : Color(white: 0.94), in: Capsule())
        }
        .buttonStyle(.plain)
        .handTarget(id, hovered: hoveredGlobalTarget)
    }

    private func togglePill(isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: { SoundEngine.shared.playClick(); action() }) {
            HStack(spacing: 6) {
                Circle().fill(.white).frame(width: 24, height: 24)
            }
            .frame(width: 56, height: 32, alignment: isOn ? .trailing : .leading)
            .padding(.horizontal, 4)
            .background(isOn ? Color.green : Color(white: 0.85), in: Capsule())
            .animation(.easeOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
        .handTarget(id, hovered: hoveredGlobalTarget)
    }

    private func settingRow<Content: View>(icon: String, title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.42, blue: 0.52))
                    .frame(width: 30, height: 30)
                    .background(Color(white: 0.94), in: Circle())
                Text(title)
                    .font(AppFont.swiftUIFont(size: 16.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 8)
    }
}
