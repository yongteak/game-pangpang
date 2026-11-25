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
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(minWidth: 184, minHeight: 50)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.89, blue: 0.29), Color(red: 0.97, green: 0.70, blue: 0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Capsule()
                            )
                            .shadow(color: Color.orange.opacity(0.35), radius: 12, y: 5)
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

struct PlayerSegmentPill: View {
    @Binding var players: Int

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
                .font(.system(size: 14, weight: .heavy))
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
                .font(.system(size: 14, weight: .heavy))
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
        }
        .padding(4)
        .background(.white.opacity(0.95), in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }
}

// MARK: - 2. Stage Select Screen (1:1 Mockup + Gentle Card Float + High-Visibility 1P/2P Toggle)
struct StageSelectView: View {
    @ObservedObject var settings: AppSettings
    let onBack: () -> Void
    let onSelectGame: (GameType) -> Void
    let onOpenSettings: () -> Void

    @State private var floatCard = false
    @State private var featured: GameType = .fruit

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color(red: 0.78, green: 0.92, blue: 1.0), Color(red: 1.0, green: 0.98, blue: 0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Button(action: { SoundEngine.shared.playClick(); onBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
                            .frame(width: 44, height: 44)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                    }

                    Spacer()
                    Text("놀이 고르기")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.27))
                    Spacer()

                    HStack(spacing: 10) {
                        PlayerSegmentPill(players: $settings.players)
                        Button(action: { SoundEngine.shared.playClick(); onOpenSettings() }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color(red: 0.29, green: 0.35, blue: 0.44))
                                .frame(width: 44, height: 44)
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 0)

                HStack(spacing: 20) {
                    ForEach(Array(GameType.allCases.enumerated()), id: \.element.id) { idx, game in
                        let isFeat = featured == game
                        let lvl = game.intensityLevel(quietMode: settings.quietMode)
                        Button(action: {
                            SoundEngine.shared.playClick()
                            featured = game
                            onSelectGame(game)
                        }) {
                            VStack(spacing: 10) {
                                BundleImage.swiftUIImage(named: game.cardImageName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 132)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                                Text(game.title)
                                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.27))

                                HStack(spacing: 4) {
                                    ForEach(0..<lvl, id: \.self) { _ in
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(lvl == 1 ? .green : lvl == 2 ? .orange : .red)
                                    }
                                    Text(game.intensityLabel(quietMode: settings.quietMode))
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(lvl == 1 ? Color(red: 0.17, green: 0.54, blue: 0.34) : lvl == 2 ? Color(red: 0.79, green: 0.41, blue: 0.07) : Color(red: 0.84, green: 0.24, blue: 0.29))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    (lvl == 1 ? Color.green : lvl == 2 ? Color.orange : Color.red).opacity(0.12),
                                    in: Capsule()
                                )
                            }
                            .padding(12)
                            .frame(maxWidth: 230)
                            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(isFeat ? Color(red: 1.0, green: 0.85, blue: 0.30) : .white, lineWidth: 4)
                            )
                            .shadow(color: isFeat ? Color.yellow.opacity(0.3) : .black.opacity(0.1), radius: 14, y: 6)
                            .offset(y: floatCard ? -6 : 0)
                            .animation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true).delay(Double(idx) * 0.5), value: floatCard)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)

                if settings.quietMode {
                    Text("🪶 층간소음 모드 ON · 팔과 상체로 조용히 즐겨요")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.24, green: 0.48, blue: 0.47))
                        .padding(.bottom, 6)
                }
            }

            // Bottom-right peeking mascots
            HStack(spacing: -14) {
                BundleImage.swiftUIImage(named: "momo_head").resizable().scaledToFit().frame(width: 68)
                BundleImage.swiftUIImage(named: "popo_head").resizable().scaledToFit().frame(width: 72)
            }
            .padding(.trailing, 14)
            .offset(y: 12)
            .allowsHitTesting(false)
        }
        .onAppear { floatCard = true }
    }
}

// MARK: - 5. Minimal Parent Settings Modal (1:1 Mockup + Dev Mode Toggle)
struct SettingsModalView: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.36).ignoresSafeArea()
                .onTapGesture { SoundEngine.shared.playClick(); onClose() }

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    HStack {
                        Color.clear.frame(width: 32, height: 32)
                        Spacer()
                        Text("설정")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                        Spacer()
                        Button(action: { SoundEngine.shared.playClick(); onClose() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.gray)
                                .frame(width: 32, height: 32)
                                .background(Color(white: 0.93), in: Circle())
                        }
                    }
                    .padding(.bottom, 10)

                    // Row 1: Players
                    settingRow(icon: "person.2.fill", title: "플레이 인원") {
                        Picker("", selection: $settings.players) {
                            Text("1인").tag(1)
                            Text("2인").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                    }
                    Divider()

                    // Row 2: Quiet Mode
                    settingRow(icon: "leaf.fill", title: "층간소음 모드") {
                        Toggle("", isOn: $settings.quietMode).labelsHidden()
                    }
                    Divider()

                    // Row 3: Play Speed
                    settingRow(icon: "gauge.medium", title: "놀이 속도") {
                        Picker("", selection: $settings.speedRaw) {
                            ForEach(PlaySpeed.allCases, id: \.rawValue) { sp in
                                Text(sp.label).tag(sp.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    Divider()

                    // Row 4: Sound & AirPlay TV
                    settingRow(icon: "speaker.wave.2.fill", title: "소리 · TV 연결") {
                        HStack(spacing: 10) {
                            Slider(value: $settings.volume, in: 0...1)
                                .frame(width: 90)
                                .onChange(of: settings.volume) { _, newVal in
                                    SoundEngine.shared.volume = Float(newVal)
                                }
                            HStack(spacing: 4) {
                                AirPlayButton().frame(width: 24, height: 24)
                                Text("AirPlay TV")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.95), in: Capsule())
                        }
                    }
                    Divider()

                    // Row 5: Developer Mode (Touch/Drag Test without Camera)
                    settingRow(icon: "hammer.fill", title: "개발자 모드 (터치 테스트)") {
                        Toggle("", isOn: $settings.devMode).labelsHidden()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 510)
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    private func settingRow<Content: View>(icon: String, title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.42, blue: 0.52))
                    .frame(width: 30, height: 30)
                    .background(Color(white: 0.94), in: Circle())
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 8)
    }
}
