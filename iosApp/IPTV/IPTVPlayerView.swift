import SwiftUI
import UIKit
import AVFoundation

// MARK: - Player Surface Representable (Always Fullscreen)

/// The MPV surface permanently fills the whole screen. It is NEVER moved, resized
/// or remounted, so inline <-> fullscreen transitions cannot misplace the video:
///
/// - Inline (portrait): the UI lives below a full-width 16:9 "window" at the top
///   of the screen; mpv aligns the video to the top of the surface
///   (video-align-y = -1), so it lands exactly inside that window.
/// - Fullscreen: the inline UI hides and the same surface stays visible
///   edge-to-edge while the orientation lock rotates to landscape.
struct IPTVPlayerSurfaceRepresentable: UIViewControllerRepresentable {
    let playerVC: MPVPlayerViewController

    func makeUIViewController(context: Context) -> MPVPlayerViewController {
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerVC.alignVideoToTop()
        IPTVPiPCoordinator.shared.configure(sourceView: playerVC.view)
        return playerVC
    }

    func updateUIViewController(_ uiViewController: MPVPlayerViewController, context: Context) {
        uiViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}

// MARK: - IPTV Player Screen

public struct IPTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = IPTVPlaylistStore.shared
    @ObservedObject private var pipCoordinator = IPTVPiPCoordinator.shared

    @State public var currentChannel: IPTVChannel
    public let playlistChannels: [IPTVChannel]

    // Player State
    @State private var playerVC = MPVPlayerViewController()
    @State private var isPlaying: Bool = true
    @State private var isFullscreen: Bool = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Task<Void, Never>? = nil
    @State private var showFullscreenDrawer: Bool = false
    @State private var showAudioTrackSheet: Bool = false
    @State private var currentResizeIndex: Int = 0

    // Inline Channel Browser
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
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let isCinema = isFullscreen || isLandscape
            // The 16:9 video window at the top of the screen (portrait inline mode).
            // mpv's video-align-y = -1 makes the video occupy exactly this band.
            let bandHeight = (geometry.size.width * 9 / 16).rounded()

            ZStack(alignment: .topLeading) {
                // 1. Video surface: permanent, full-screen, never moved or resized.
                IPTVPlayerSurfaceRepresentable(playerVC: playerVC)
                    .ignoresSafeArea()

                // 2. Inline UI (portrait): everything lives BELOW the video window.
                if !isCinema {
                    VStack(spacing: 0) {
                        // Transparent "window" the video shows through.
                        Color.clear
                            .frame(width: geometry.size.width, height: bandHeight)

                        VStack(spacing: 0) {
                            searchAndGroupsBar
                            channelsScrollView
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }

                // 3. Inline controls floating on the video window.
                if !isCinema {
                    inlineBandOverlay
                        .frame(width: geometry.size.width, height: bandHeight)
                        .position(x: geometry.size.width / 2, y: bandHeight / 2)
                        .zIndex(15)
                }

                // 4. Cinema / fullscreen controls.
                if isCinema {
                    fullscreenOverlay(geometry: geometry)
                        .zIndex(20)
                }
            }
            .onChange(of: isCinema) { cinema in
                if !cinema {
                    // Fill/zoom (panscan) zooms into the WHOLE surface, which would
                    // bleed over the inline UI - only allow it in fullscreen.
                    if currentResizeIndex != 0 {
                        currentResizeIndex = 0
                        playerVC.setResize(0)
                    }
                    showFullscreenDrawer = false
                }
                resetControlsTimer()
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden(isFullscreen)
        .onAppear {
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

    // MARK: - Inline Band Overlay (controls floating on the video window)

    private var inlineBandOverlay: some View {
        ZStack {
            // Tap area to toggle controls
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                    if showControls { resetControlsTimer() }
                }

            if showControls {
                Color.black.opacity(0.25)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Top row: Back / Title / PiP / Favorite
                    HStack(spacing: 10) {
                        Button {
                            handleDismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.45), in: Circle())
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(currentChannel.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(currentChannel.groupTitle.isEmpty ? "Truyền hình trực tiếp" : currentChannel.groupTitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        if pipCoordinator.isPiPSupported {
                            Button {
                                pipCoordinator.togglePiP()
                            } label: {
                                Image(systemName: pipCoordinator.isPiPActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(pipCoordinator.isPiPActive ? .cyan : .white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.45), in: Circle())
                            }
                        }

                        Button {
                            store.toggleFavorite(channel: currentChannel)
                        } label: {
                            Image(systemName: store.isFavorite(channel: currentChannel) ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(store.isFavorite(channel: currentChannel) ? .yellow : .white)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.45), in: Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, max(windowSafeAreaInsets.top, 8) + 4)

                    Spacer()

                    // Bottom row: LIVE badge / Fullscreen button
                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(Color.white).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red, in: Capsule())

                        Spacer()

                        Button {
                            enterFullscreen()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.45), in: Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .transition(.opacity)

                // Center Play / Pause
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Search & Groups Bar

    private var searchAndGroupsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.gray)
                TextField("Tìm kiếm nhanh trong danh sách kênh...", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Nhóm kênh (Filter Chips)
            if availableGroups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableGroups, id: \.self) { grp in
                            let isSel = selectedGroup == grp
                            Button {
                                withAnimation { selectedGroup = grp }
                            } label: {
                                Text(grp)
                                    .font(.system(size: 12, weight: isSel ? .bold : .regular))
                                    .foregroundStyle(isSel ? .black : .white.opacity(0.85))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(isSel ? Color.cyan : Color.white.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Channel List (Portrait)

    private var channelsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredChannels) { ch in
                    let isCurrent = ch.id == currentChannel.id || ch.streamUrl == currentChannel.streamUrl
                    Button {
                        switchChannel(to: ch)
                    } label: {
                        HStack(spacing: 12) {
                            if let logo = ch.logoUrl, let url = URL(string: logo) {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "tv.fill").foregroundStyle(.gray)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "tv.fill")
                                    .foregroundStyle(.gray)
                                    .frame(width: 34, height: 34)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ch.name)
                                    .font(.system(size: 14, weight: isCurrent ? .bold : .medium))
                                    .foregroundStyle(isCurrent ? .cyan : .white)
                                    .lineLimit(1)
                                Text(ch.groupTitle.isEmpty ? "IPTV" : ch.groupTitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.5))
                            }

                            Spacer()

                            if isCurrent {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform")
                                        .font(.caption2)
                                    Text("Đang phát")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.18), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isCurrent ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04),
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

    // MARK: - Fullscreen Overlay (Cinema Mode)

    private func fullscreenOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            // Tap surface to toggle fullscreen controls
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
                        Button {
                            exitFullscreen()
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
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.65), in: Capsule())

                        Spacer()

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

                        // Exit Fullscreen Button
                        Button {
                            exitFullscreen()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                        }

                        // Channel Drawer Button
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showFullscreenDrawer.toggle()
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

            // Quick Channel Drawer in Fullscreen
            if showFullscreenDrawer {
                HStack(spacing: 0) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Danh Sách Kênh")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                withAnimation { showFullscreenDrawer = false }
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

                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(playlistChannels) { ch in
                                    let isCurrent = ch.id == currentChannel.id || ch.streamUrl == currentChannel.streamUrl
                                    Button {
                                        switchChannel(to: ch)
                                        withAnimation { showFullscreenDrawer = false }
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
                    .frame(width: 280)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .vertical)
                }
                .transition(.move(edge: .trailing))
            }
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
            decryptionKey: ch.licenseKey
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

    private func enterFullscreen() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isFullscreen = true
        }
        NotificationCenter.default.post(name: Notification.Name("NuvioPlayerLockLandscape"), object: nil)
        resetControlsTimer()
    }

    private func exitFullscreen() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isFullscreen = false
            showFullscreenDrawer = false
        }
        OrientationLockCoordinator.shared.rotateToPortrait()
        resetControlsTimer()
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
                    if !showFullscreenDrawer && !showAudioTrackSheet {
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
