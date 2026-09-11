import SwiftUI
import UIKit
import AVFoundation

// MARK: - Dedicated IPTV MPV Host View Controller

final class IPTVSurfaceHostController: UIViewController {
    private let playerVC: MPVPlayerViewController
    private var channel: IPTVChannel
    private var hasStartedInitialLoad = false

    init(playerVC: MPVPlayerViewController, channel: IPTVChannel) {
        self.playerVC = playerVC
        self.channel = channel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(playerVC)
        view.addSubview(playerVC.view)
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        playerVC.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasStartedInitialLoad {
            hasStartedInitialLoad = true
            loadChannel(channel)
        }
    }

    func updateChannel(_ newChannel: IPTVChannel) {
        self.channel = newChannel
        loadChannel(newChannel)
    }

    private func loadChannel(_ ch: IPTVChannel) {
        playerVC.updateNowPlayingMetadata(
            title: ch.name,
            subtitle: ch.groupTitle,
            artworkUrl: ch.logoUrl
        )

        playerVC.loadFile(
            ch.streamUrl,
            audioUrl: nil,
            requestHeaders: ch.httpHeaders,
            subtitles: [],
            decryptionKey: ch.licenseKey
        )
        playerVC.playPlayback()
    }
}

struct IPTVSurfaceRepresentable: UIViewControllerRepresentable {
    let playerVC: MPVPlayerViewController
    let channel: IPTVChannel

    func makeUIViewController(context: Context) -> IPTVSurfaceHostController {
        IPTVSurfaceHostController(playerVC: playerVC, channel: channel)
    }

    func updateUIViewController(_ uiViewController: IPTVSurfaceHostController, context: Context) {
        uiViewController.updateChannel(channel)
    }
}

// MARK: - IPTV Player View (Overlay phong cách Nuvio Cinema Player)

public struct IPTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store = IPTVPlaylistStore.shared
    @State public var currentChannel: IPTVChannel
    public let playlistChannels: [IPTVChannel]

    // Player State
    @State private var playerVC = MPVPlayerViewController()
    @State private var showControls: Bool = true
    @State private var showChannelDrawer: Bool = false
    @State private var showAudioTrackSheet: Bool = false
    @State private var isPlaying: Bool = true
    @State private var isLoading: Bool = true
    @State private var currentResizeIndex: Int = 0
    @State private var isLandscapeLocked: Bool = false
    @State private var hideControlsTask: Task<Void, Never>? = nil

    // Touch Controls
    @State private var brightnessLevel: CGFloat = UIScreen.main.brightness
    @State private var showBrightnessHUD: Bool = false
    @State private var brightnessHUDTask: Task<Void, Never>? = nil

    // Drawer Search
    @State private var drawerSearchText: String = ""

    private let resizeModes: [(title: String, icon: String, mode: Int)] = [
        ("Vừa màn hình", "arrow.down.right.and.arrow.up.left", 0),
        ("Cắt tràn viền (Fill)", "arrow.up.left.and.arrow.down.right", 1),
        ("Phóng to 16:9", "aspectratio", 2)
    ]

    public init(channel: IPTVChannel, playlistChannels: [IPTVChannel] = []) {
        self._currentChannel = State(initialValue: channel)
        self.playlistChannels = playlistChannels.isEmpty ? IPTVPlaylistStore.shared.currentChannels : playlistChannels
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 1. MPV Video Surface
            IPTVSurfaceRepresentable(playerVC: playerVC, channel: currentChannel)
                .ignoresSafeArea()
                .onTapGesture {
                    toggleControls()
                }

            // 2. Gesture Controls (Vuốt tăng/giảm độ sáng bên trái)
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                let delta = -value.translation.height / 350.0
                                let nextVal = min(max(brightnessLevel + delta, 0.05), 1.0)
                                UIScreen.main.brightness = nextVal
                                brightnessLevel = nextVal
                                showBrightnessHUD = true
                                scheduleBrightnessHUDHide()
                            }
                    )
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleControls()
                    }
            }
            .ignoresSafeArea()

            // 3. Brightness HUD Popup
            if showBrightnessHUD {
                VStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.yellow)
                    ProgressView(value: Double(brightnessLevel), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .yellow))
                        .frame(width: 110)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
            }

            // 4. Loading Spinner
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        .scaleEffect(1.5)
                    Text("Đang mở luồng phát...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(22)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
            }

            // 5. Controls Overlay (Phong cách Cinema Player)
            if showControls {
                playerControlsOverlay
                    .transition(.opacity)
            }

            // 6. Quick Zapping Drawer (Menu chuyển kênh nhanh)
            if showChannelDrawer {
                quickZappingDrawer
                    .transition(.move(edge: .trailing))
            }
        }
        .statusBarHidden(!showControls)
        .onAppear {
            store.recordRecent(channel: currentChannel)
            scheduleLoadingDismiss()
            scheduleHideControls()
        }
        .onDisappear {
            tearDown()
        }
        .sheet(isPresented: $showAudioTrackSheet) {
            audioTracksSheet
        }
    }

    // MARK: - Player Controls Overlay

    private var playerControlsOverlay: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }

                // Channel Info
                HStack(spacing: 10) {
                    if let logo = currentChannel.logoUrl, let url = URL(string: logo) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                            } else {
                                Image(systemName: "tv.fill").foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(currentChannel.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            // Live badge
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())

                            // MPD badge
                            if currentChannel.isMPEG_DASH {
                                Text(currentChannel.isClearKey ? "MPD • KEY" : "DASH")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.25), in: Capsule())
                            }
                        }

                        Text(currentChannel.groupTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Lock Landscape Toggle
                Button {
                    toggleOrientationLock()
                } label: {
                    Image(systemName: isLandscapeLocked ? "lock.rotation" : "lock.rotation.open")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isLandscapeLocked ? .cyan : .white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }

                // Aspect Ratio Toggle
                Button {
                    cycleResize()
                } label: {
                    Image(systemName: resizeModes[currentResizeIndex].icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }

                // Favorite Button
                Button {
                    store.toggleFavorite(channel: currentChannel)
                } label: {
                    Image(systemName: store.isFavorite(channel: currentChannel) ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.isFavorite(channel: currentChannel) ? .yellow : .white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }

                // Drawer Button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showChannelDrawer.toggle()
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            // Center Play / Pause
            HStack(spacing: 50) {
                // Prev Channel
                Button {
                    switchAdjacent(forward: false)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 50, height: 50)
                }

                // Big Play / Pause Toggle
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(.ultraThinMaterial.opacity(0.95), in: Circle())
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        }
                }

                // Next Channel
                Button {
                    switchAdjacent(forward: true)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 50, height: 50)
                }
            }

            Spacer()

            // Bottom Bar
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("TRUYỀN HÌNH TRỰC TIẾP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Audio Track Selection
                Button {
                    showAudioTrackSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                        Text("Âm thanh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                // Reload stream
                Button {
                    reloadStream()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.75), .clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    // MARK: - Quick Zapping Drawer

    private var filteredDrawerChannels: [IPTVChannel] {
        let q = drawerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return playlistChannels }
        return playlistChannels.filter { $0.name.lowercased().contains(q) || $0.groupTitle.lowercased().contains(q) }
    }

    private var quickZappingDrawer: some View {
        HStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // Drawer Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Danh Sách Kênh")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(playlistChannels.count) kênh")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                    Button {
                        withAnimation { showChannelDrawer = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Drawer Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    TextField("Tìm nhanh kênh...", text: $drawerSearchText)
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(8)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

                // Channel List
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredDrawerChannels) { ch in
                            let isCurrent = ch.id == currentChannel.id || ch.streamUrl == currentChannel.streamUrl
                            Button {
                                changeChannel(to: ch)
                                withAnimation { showChannelDrawer = false }
                            } label: {
                                HStack(spacing: 10) {
                                    if let logo = ch.logoUrl, let url = URL(string: logo) {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFit()
                                            } else {
                                                Image(systemName: "tv.fill").foregroundStyle(.gray)
                                            }
                                        }
                                        .frame(width: 32, height: 32)
                                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "tv.fill")
                                            .foregroundStyle(.gray)
                                            .frame(width: 32, height: 32)
                                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.name)
                                            .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                                            .foregroundStyle(isCurrent ? .cyan : .white)
                                            .lineLimit(1)
                                        Text(ch.groupTitle)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    if isCurrent {
                                        Image(systemName: "waveform")
                                            .font(.caption)
                                            .foregroundStyle(.cyan)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    isCurrent ? Color.cyan.opacity(0.18) : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .vertical)
        }
    }

    // MARK: - Audio Tracks Sheet

    private var audioTracksSheet: some View {
        NavigationStack {
            List {
                let count = Int(playerVC.audioTracks.count)
                if count == 0 {
                    Text("Chỉ có 1 luồng âm thanh mặc định")
                        .foregroundStyle(.gray)
                } else {
                    ForEach(0..<count, id: \.self) { idx in
                        let track = playerVC.audioTracks[idx]
                        Button {
                            playerVC.selectAudio(track.id)
                            showAudioTrackSheet = false
                        } label: {
                            HStack {
                                Text(track.title.isEmpty ? "Âm thanh \(idx + 1)" : track.title)
                                    .foregroundStyle(.white)
                                Spacer()
                                if track.selected {
                                    Image(systemName: "checkmark").foregroundStyle(.cyan)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chọn Ngôn Ngữ Âm Thanh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showAudioTrackSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions & Controls

    private func changeChannel(to newChannel: IPTVChannel) {
        currentChannel = newChannel
        store.recordRecent(channel: newChannel)
        isLoading = true
        scheduleLoadingDismiss()
        scheduleHideControls()
    }

    private func reloadStream() {
        isLoading = true
        playerVC.retryPlayback()
        scheduleLoadingDismiss()
    }

    private func togglePlayPause() {
        if isPlaying {
            playerVC.pausePlayback()
            isPlaying = false
        } else {
            playerVC.playPlayback()
            isPlaying = true
        }
        scheduleHideControls()
    }

    private func switchAdjacent(forward: Bool) {
        guard !playlistChannels.isEmpty else { return }
        guard let currIdx = playlistChannels.firstIndex(where: { $0.id == currentChannel.id || $0.streamUrl == currentChannel.streamUrl }) else {
            if let first = playlistChannels.first { changeChannel(to: first) }
            return
        }

        var nextIdx = forward ? (currIdx + 1) : (currIdx - 1)
        if nextIdx >= playlistChannels.count { nextIdx = 0 }
        if nextIdx < 0 { nextIdx = playlistChannels.count - 1 }
        changeChannel(to: playlistChannels[nextIdx])
    }

    private func cycleResize() {
        currentResizeIndex = (currentResizeIndex + 1) % resizeModes.count
        playerVC.setResize(resizeModes[currentResizeIndex].mode)
    }

    private func toggleOrientationLock() {
        isLandscapeLocked.toggle()
        let notifName = isLandscapeLocked ? "NuvioPlayerLockLandscape" : "NuvioPlayerUnlockOrientation"
        NotificationCenter.default.post(name: Notification.Name(notifName), object: nil)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleHideControls()
        } else {
            hideControlsTask?.cancel()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if !showChannelDrawer && !showAudioTrackSheet {
                        self.showControls = false
                    }
                }
            }
        }
    }

    private func scheduleLoadingDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    private func scheduleBrightnessHUDHide() {
        brightnessHUDTask?.cancel()
        brightnessHUDTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { self.showBrightnessHUD = false }
            }
        }
    }

    private func tearDown() {
        hideControlsTask?.cancel()
        playerVC.pausePlayback()
        playerVC.clearNowPlayingInfo()
        playerVC.destroyPlayer()
        if isLandscapeLocked {
            NotificationCenter.default.post(name: Notification.Name("NuvioPlayerUnlockOrientation"), object: nil)
        }
    }
}
