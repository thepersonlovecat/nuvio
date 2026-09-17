import SwiftUI
import UIKit
import AVFoundation

// MARK: - Player Surface Representable (Permanent Fullscreen)

/// The MPV surface fills the entire screen for the whole lifetime of the player.
/// It is never moved, resized or remounted, so there are no inline/fullscreen
/// transitions that could misplace the video.
struct IPTVPlayerSurfaceRepresentable: UIViewControllerRepresentable {
    let playerVC: MPVPlayerViewController

    func makeUIViewController(context: Context) -> MPVPlayerViewController {
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        IPTVPiPCoordinator.shared.configure(sourceView: playerVC.view)
        return playerVC
    }

    func updateUIViewController(_ uiViewController: MPVPlayerViewController, context: Context) {
        uiViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}

// MARK: - IPTV Player Screen (Fullscreen-First)

/// Fullscreen-first live TV player: tapping a channel in the catalog opens this
/// screen, rotates to landscape and starts playback edge-to-edge immediately.
/// All channel browsing happens in the in-player drawer. There is intentionally
/// NO inline/mini-player mode.
public struct IPTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = IPTVPlaylistStore.shared
    @ObservedObject private var pipCoordinator = IPTVPiPCoordinator.shared

    @State public var currentChannel: IPTVChannel
    public let playlistChannels: [IPTVChannel]

    // Player State
    @State private var playerVC = MPVPlayerViewController()
    @State private var isPlaying: Bool = true
    @State private var showControls: Bool = true
    @State private var controlsTimer: Task<Void, Never>? = nil
    @State private var showChannelDrawer: Bool = false
    @State private var showAudioTrackSheet: Bool = false
    @State private var currentResizeIndex: Int = 0

    // Drawer Channel Browser
    @State private var searchText: String = ""
    @State private var selectedGroup: String = "Tất cả"

    private let resizeModes: [(title: String, icon: String, mode: Int)] = [
        ("Vừa màn hình", "arrow.down.right.and.arrow.up.left", 0),
        ("Cắt tràn viền (Fill)", "arrow.up.left.and.arrow.down.right", 1),
        ("Phóng to 16:9", "aspectratio", 2)
    ]

    public init(channel: IPTVChannel, playlistChannels: [IPTVChannel] = []) {
        self._currentChannel = State(initialValue: channel)
        self.playlistChannels = playlistChannels.isEmpty ? IPTVPlaylistStore.shared.currentChannels : playlistChannels
    }

    private var availableGroups: [String] {
        var set = Set<String>()
        playlistChannels.forEach { ch in
            if !ch.groupTitle.isEmpty { set.insert(ch.groupTitle) }
        }
        return ["Tất cả"] + Array(set).sorted()
    }

    private var filteredChannels: [IPTVChannel] {
        playlistChannels.filter { ch in
            let matchesGroup = selectedGroup == "Tất cả" || ch.groupTitle == selectedGroup
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = q.isEmpty || ch.name.lowercased().contains(q) || ch.groupTitle.lowercased().contains(q)
            return matchesGroup && matchesSearch
        }
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
    }

    public var body: some View {
        ZStack {
            // Video surface: permanent, full-screen.
            IPTVPlayerSurfaceRepresentable(playerVC: playerVC)
                .ignoresSafeArea()

            // Controls overlay.
            controlsOverlay
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden(true)
        .onAppear {
            // Fullscreen-first: lock to landscape as soon as the player opens.
            NotificationCenter.default.post(name: Notification.Name("NuvioPlayerLockLandscape"), object: nil)
            store.recordRecent(channel: currentChannel)
            loadChannel(currentChannel)
            resetControlsTimer()
        }
        .onDisappear {
            tearDown()
        }
        .sheet(isPresented: $showAudioTrackSheet) {
            audioTracksSheet
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        ZStack {
            // Tap surface to toggle controls
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                    if showControls { resetControlsTimer() }
                }

            if showControls {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack {
                    // Top Bar
                    HStack(spacing: 12) {
                        // Back to catalog (auto-rotates back to portrait)
                        Button {
                            handleDismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        // Channel Title Capsule
                        HStack(spacing: 8) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text(currentChannel.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if currentChannel.isClearKey {
                                HStack(spacing: 3) {
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 8, weight: .black))
                                    Text(currentChannel.isMPEG_DASH ? "MPD DRM" : "DRM")
                                        .font(.system(size: 9, weight: .heavy))
                                }
                                .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.25))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.2), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.65), in: Capsule())

                        Spacer()

                        // PiP
                        if pipCoordinator.isPiPSupported {
                            Button {
                                pipCoordinator.togglePiP()
                            } label: {
                                Image(systemName: pipCoordinator.isPiPActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(pipCoordinator.isPiPActive ? .cyan : .white)
                                    .frame(width: 38, height: 38)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }

                        // Favorite
                        Button {
                            store.toggleFavorite(channel: currentChannel)
                        } label: {
                            Image(systemName: store.isFavorite(channel: currentChannel) ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(store.isFavorite(channel: currentChannel) ? .yellow : .white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        // Aspect Ratio Toggle
                        Button {
                            cycleResize()
                        } label: {
                            Image(systemName: resizeModes[currentResizeIndex].icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        // Audio Language Sheet
                        Button {
                            showAudioTrackSheet = true
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        // Channel Drawer Button
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showChannelDrawer.toggle()
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.leading, max(windowSafeAreaInsets.left, 20))
                    .padding(.trailing, max(windowSafeAreaInsets.right, 20))
                    .padding(.top, max(windowSafeAreaInsets.top, 14))

                    Spacer()

                    // Center Prev / Play-Pause / Next
                    HStack(spacing: 44) {
                        Button {
                            switchAdjacent(forward: false)
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 44, height: 44)
                        }

                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 66, height: 66)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        Button {
                            switchAdjacent(forward: true)
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 44, height: 44)
                        }
                    }

                    Spacer()

                    // Bottom Bar
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("TRUYỀN HÌNH TRỰC TIẾP")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                        }

                        Spacer()

                        Button {
                            reloadStream()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.leading, max(windowSafeAreaInsets.left, 24))
                    .padding(.trailing, max(windowSafeAreaInsets.right, 24))
                    .padding(.bottom, max(windowSafeAreaInsets.bottom, 16))
                }
                .transition(.opacity)
            }

            // Channel Drawer (search + groups + channel list)
            if showChannelDrawer {
                HStack(spacing: 0) {
                    Spacer()
                    channelDrawer
                }
                .transition(.move(edge: .trailing))
            }
        }
    }

    // MARK: - Channel Drawer

    private var channelDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Danh Sách Kênh")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation { showChannelDrawer = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.gray)
                TextField("Tìm kênh...", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)

            // Group filter chips
            if availableGroups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableGroups, id: \.self) { grp in
                            let isSel = selectedGroup == grp
                            Button {
                                withAnimation { selectedGroup = grp }
                            } label: {
                                Text(grp)
                                    .font(.system(size: 11, weight: isSel ? .bold : .regular))
                                    .foregroundStyle(isSel ? .black : .white.opacity(0.85))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSel ? Color.cyan : Color.white.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredChannels) { ch in
                        let isCurrent = ch.id == currentChannel.id || ch.streamUrl == currentChannel.streamUrl
                        Button {
                            switchChannel(to: ch)
                            withAnimation { showChannelDrawer = false }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "tv")
                                    .font(.caption)
                                    .foregroundStyle(isCurrent ? .cyan : .gray)
                                Text(ch.name)
                                    .font(.system(size: 13, weight: isCurrent ? .bold : .regular))
                                    .foregroundStyle(isCurrent ? .cyan : .white)
                                    .lineLimit(1)
                                Spacer()
                                if isCurrent {
                                    Circle().fill(Color.cyan).frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isCurrent ? Color.cyan.opacity(0.2) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .vertical)
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

    // MARK: - Playback Logic & Actions

    private func loadChannel(_ ch: IPTVChannel) {
        playerVC.stopPlayback()
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
            decryptionKey: ch.licenseKey,
            isDash: ch.isMPEG_DASH
        )
        playerVC.playPlayback()
        isPlaying = true
    }

    private func switchChannel(to newChannel: IPTVChannel) {
        guard currentChannel.id != newChannel.id || currentChannel.streamUrl != newChannel.streamUrl else { return }
        playerVC.stopPlayback()
        currentChannel = newChannel
        store.recordRecent(channel: newChannel)
        loadChannel(newChannel)
        resetControlsTimer()
    }

    private func togglePlayPause() {
        if isPlaying {
            playerVC.pausePlayback()
            isPlaying = false
        } else {
            playerVC.playPlayback()
            isPlaying = true
        }
        resetControlsTimer()
    }

    private func reloadStream() {
        playerVC.retryPlayback()
        isPlaying = true
        resetControlsTimer()
    }

    private func switchAdjacent(forward: Bool) {
        guard !playlistChannels.isEmpty else { return }
        guard let currIdx = playlistChannels.firstIndex(where: { $0.id == currentChannel.id || $0.streamUrl == currentChannel.streamUrl }) else {
            if let first = playlistChannels.first { switchChannel(to: first) }
            return
        }
        var nextIdx = forward ? (currIdx + 1) : (currIdx - 1)
        if nextIdx >= playlistChannels.count { nextIdx = 0 }
        if nextIdx < 0 { nextIdx = playlistChannels.count - 1 }
        switchChannel(to: playlistChannels[nextIdx])
    }

    private func cycleResize() {
        currentResizeIndex = (currentResizeIndex + 1) % resizeModes.count
        playerVC.setResize(resizeModes[currentResizeIndex].mode)
    }

    private func handleDismiss() {
        tearDown()
        dismiss()
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if !showChannelDrawer && !showAudioTrackSheet {
                        showControls = false
                    }
                }
            }
        }
    }

    private func tearDown() {
        controlsTimer?.cancel()
        playerVC.stopPlayback()
        playerVC.clearNowPlayingInfo()
        playerVC.destroyPlayer()
        OrientationLockCoordinator.shared.rotateToPortrait()
    }
}
