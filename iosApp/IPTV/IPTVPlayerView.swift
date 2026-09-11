import SwiftUI
import UIKit
import AVFoundation

// MARK: - MPV Surface Controller Representable

struct MPVPlayerRepresentable: UIViewControllerRepresentable {
    let controller: MPVPlayerViewController

    func makeUIViewController(context: Context) -> MPVPlayerViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: MPVPlayerViewController, context: Context) {
        // MPV tự quản lý layout layer
    }
}

// MARK: - IPTV Player View

public struct IPTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store = IPTVPlaylistStore.shared
    @State public var currentChannel: IPTVChannel
    public let playlistChannels: [IPTVChannel]

    // Player State
    @State private var playerVC: MPVPlayerViewController? = nil
    @State private var showControls: Bool = true
    @State private var showChannelDrawer: Bool = false
    @State private var isPlaying: Bool = true
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var hideControlsTask: Task<Void, Never>? = nil
    @State private var currentResizeModeIndex: Int = 0

    // Volume & Brightness Gesture State
    @State private var brightnessLevel: CGFloat = UIScreen.main.brightness
    @State private var showBrightnessIndicator: Bool = false
    @State private var brightnessHideTask: Task<Void, Never>? = nil

    private let resizeModes: [(name: String, mode: Int32)] = [
        ("Vừa màn hình", 0),
        ("Cắt viền (Fill)", 1),
        ("16:9", 2),
        ("4:3", 3)
    ]

    public init(channel: IPTVChannel, playlistChannels: [IPTVChannel] = []) {
        self._currentChannel = State(initialValue: channel)
        self.playlistChannels = playlistChannels.isEmpty ? IPTVPlaylistStore.shared.currentChannels : playlistChannels
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // MPV Surface
            if let playerVC {
                MPVPlayerRepresentable(controller: playerVC)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }
            }

            // Gesture Overlay for Brightness
            HStack(spacing: 0) {
                // Nửa trái: chỉnh độ sáng
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let delta = -value.translation.height / 300.0
                                let newBrightness = min(max(brightnessLevel + delta, 0.05), 1.0)
                                UIScreen.main.brightness = newBrightness
                                brightnessLevel = newBrightness
                                showBrightnessIndicator = true
                                scheduleBrightnessHide()
                            }
                    )

                // Nửa phải: tap để hiện controls
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleControls()
                    }
            }
            .ignoresSafeArea()

            // Indicator Độ Sáng
            if showBrightnessIndicator {
                VStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.yellow)
                    ProgressView(value: Double(brightnessLevel), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .yellow))
                        .frame(width: 100)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
            }

            // Loading Spinner
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                    Text("Đang kết nối luồng phát...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(20)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            }

            // Error Overlay
            if let error = errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.yellow)
                    Text("Không thể phát kênh này")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button {
                        playChannel(currentChannel)
                    } label: {
                        Label("Thử lại", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white, in: Capsule())
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(30)
            }

            // Controls Overlay
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }

            // Zapping Drawer (Menu chuyển kênh nhanh bên phải)
            if showChannelDrawer {
                channelDrawer
                    .transition(.move(edge: .trailing))
            }
        }
        .statusBarHidden(!showControls)
        .onAppear {
            setupPlayer()
            playChannel(currentChannel)
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                }

                // Channel Info Header
                HStack(spacing: 10) {
                    if let logo = currentChannel.logoUrl, let url = URL(string: logo) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                            } else {
                                Image(systemName: "tv")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(currentChannel.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            // Live badge
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85), in: Capsule())

                            // MPD / ClearKey badge
                            if currentChannel.isMPEG_DASH {
                                Text(currentChannel.isClearKey ? "MPD • KEY" : "DASH")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.2), in: Capsule())
                            }
                        }

                        Text(currentChannel.groupTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Favorite Button
                Button {
                    store.toggleFavorite(channel: currentChannel)
                } label: {
                    Image(systemName: store.isFavorite(channel: currentChannel) ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(store.isFavorite(channel: currentChannel) ? .yellow : .white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                }

                // Aspect Ratio Button
                Button {
                    cycleResizeMode()
                } label: {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                }

                // Quick Channel List Button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showChannelDrawer.toggle()
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()

            // Bottom Bar (Channel Switching Controls)
            HStack(spacing: 32) {
                // Kênh trước
                Button {
                    switchToAdjacentChannel(forward: false)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                        Text("Kênh trước")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white)
                }

                // Pause / Resume Playback
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                // Kênh kế
                Button {
                    switchToAdjacentChannel(forward: true)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                        Text("Kênh kế")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    // MARK: - Quick Channel Drawer (Zapping)

    private var channelDrawer: some View {
        HStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Danh Sách Kênh")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        withAnimation { showChannelDrawer = false }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(playlistChannels) { ch in
                            Button {
                                playChannel(ch)
                                withAnimation { showChannelDrawer = false }
                            } label: {
                                HStack(spacing: 10) {
                                    if let logo = ch.logoUrl, let url = URL(string: logo) {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFit()
                                            } else {
                                                Image(systemName: "tv").foregroundStyle(.gray)
                                            }
                                        }
                                        .frame(width: 32, height: 32)
                                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Image(systemName: "tv")
                                            .foregroundStyle(.gray)
                                            .frame(width: 32, height: 32)
                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.name)
                                            .font(.system(size: 14, weight: ch.id == currentChannel.id ? .bold : .medium))
                                            .foregroundStyle(ch.id == currentChannel.id ? .cyan : .white)
                                            .lineLimit(1)
                                        Text(ch.groupTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    if ch.id == currentChannel.id {
                                        Image(systemName: "waveform")
                                            .font(.caption)
                                            .foregroundStyle(.cyan)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    ch.id == currentChannel.id ? Color.cyan.opacity(0.15) : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            }
            .frame(width: 290)
            .background(.ultraThinMaterial)
            .ignoresSafeArea(edges: .vertical)
        }
    }

    // MARK: - Player Lifecycle & Actions

    private func setupPlayer() {
        if playerVC == nil {
            let vc = MPVPlayerViewController()
            self.playerVC = vc
        }
    }

    private func tearDownPlayer() {
        hideControlsTask?.cancel()
        playerVC?.pausePlayback()
        playerVC?.clearNowPlayingInfo()
        playerVC?.destroyPlayer()
        playerVC = nil
    }

    private func playChannel(_ channel: IPTVChannel) {
        currentChannel = channel
        store.recordRecent(channel: channel)
        errorMessage = nil
        isLoading = true

        guard let playerVC else { return }

        // Metadata Now Playing
        playerVC.updateNowPlayingMetadata(
            title: channel.name,
            subtitle: channel.groupTitle,
            artworkUrl: channel.logoUrl
        )

        // Cấu hình phát luồng với Headers và ClearKey (nếu có)
        playerVC.loadFile(
            channel.streamUrl,
            audioUrl: nil,
            requestHeaders: channel.httpHeaders,
            subtitles: [],
            decryptionKey: channel.licenseKey
        )

        playerVC.playPlayback()
        isPlaying = true

        // Theo dõi trạng thái nạp
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                self.isLoading = false
            }
        }

        scheduleHideControls()
    }

    private func togglePlayPause() {
        guard let playerVC else { return }
        if isPlaying {
            playerVC.pausePlayback()
            isPlaying = false
        } else {
            playerVC.playPlayback()
            isPlaying = true
        }
        scheduleHideControls()
    }

    private func cycleResizeMode() {
        currentResizeModeIndex = (currentResizeModeIndex + 1) % resizeModes.count
        let mode = resizeModes[currentResizeModeIndex].mode
        playerVC?.setResize(Int(mode))
    }

    private func switchToAdjacentChannel(forward: Bool) {
        guard !playlistChannels.isEmpty else { return }
        guard let currentIndex = playlistChannels.firstIndex(where: { $0.id == currentChannel.id || $0.streamUrl == currentChannel.streamUrl }) else {
            if let first = playlistChannels.first { playChannel(first) }
            return
        }

        var nextIndex = forward ? (currentIndex + 1) : (currentIndex - 1)
        if nextIndex >= playlistChannels.count { nextIndex = 0 }
        if nextIndex < 0 { nextIndex = playlistChannels.count - 1 }

        playChannel(playlistChannels[nextIndex])
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
                    if !showChannelDrawer {
                        self.showControls = false
                    }
                }
            }
        }
    }

    private func scheduleBrightnessHide() {
        brightnessHideTask?.cancel()
        brightnessHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.showBrightnessIndicator = false
                }
            }
        }
    }
}
