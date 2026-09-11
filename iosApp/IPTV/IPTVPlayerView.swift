import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

// MARK: - Native Apple AVPlayer Representable

struct NativeAVPlayerRepresentable: UIViewControllerRepresentable {
    let channel: IPTVChannel
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> NativeAVPlayerViewController {
        let vc = NativeAVPlayerViewController()
        vc.onDismiss = onDismiss
        vc.loadChannel(channel)
        return vc
    }

    func updateUIViewController(_ uiViewController: NativeAVPlayerViewController, context: Context) {
        uiViewController.updateChannelIfNeeded(channel)
    }

    static func dismantleUIViewController(_ uiViewController: NativeAVPlayerViewController, coordinator: ()) {
        uiViewController.tearDown()
    }
}

// MARK: - Native AVPlayerViewController Host

final class NativeAVPlayerViewController: AVPlayerViewController, AVPlayerViewControllerDelegate {
    var onDismiss: (() -> Void)?
    private var currentChannel: IPTVChannel?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        showsPlaybackControls = true
        allowsPictureInPicturePlayback = true
        if #available(iOS 14.2, *) {
            canStartPictureInPictureAutomaticallyFromInline = true
        }
        videoGravity = .resizeAspect
        view.backgroundColor = .black

        configureAudioSession()
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    func loadChannel(_ channel: IPTVChannel) {
        self.currentChannel = channel
        guard let url = URL(string: channel.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        var assetOptions: [String: Any] = [:]
        if !channel.httpHeaders.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = channel.httpHeaders
        }

        let asset = AVURLAsset(url: url, options: assetOptions)
        let playerItem = AVPlayerItem(asset: asset)
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        self.player = newPlayer
        
        updateNowPlaying(channel: channel)
        newPlayer.play()
    }

    func updateChannelIfNeeded(_ channel: IPTVChannel) {
        guard let current = currentChannel, current.id == channel.id, current.streamUrl == channel.streamUrl else {
            loadChannel(channel)
            return
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("[NativeAVPlayer] AudioSession error: \(error.localizedDescription)")
        }
    }

    private func updateNowPlaying(channel: IPTVChannel) {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPMediaItemPropertyArtist: channel.groupTitle.isEmpty ? "Truyền hình trực tiếp" : channel.groupTitle,
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func tearDown() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - AVPlayerViewControllerDelegate
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.onDismiss?()
        }
    }
}

// MARK: - IPTV Player View (Clean Native Presentation)

public struct IPTVPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store = IPTVPlaylistStore.shared
    @State public var currentChannel: IPTVChannel
    public let playlistChannels: [IPTVChannel]

    public init(channel: IPTVChannel, playlistChannels: [IPTVChannel] = []) {
        self._currentChannel = State(initialValue: channel)
        self.playlistChannels = playlistChannels.isEmpty ? IPTVPlaylistStore.shared.currentChannels : playlistChannels
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            // 1. Trình phát chuẩn Native Apple AVPlayer (100% mượt, tự động xoay, PiP, AirPlay)
            NativeAVPlayerRepresentable(channel: currentChannel, onDismiss: {
                handleDismiss()
            })
            .ignoresSafeArea()

            // 2. Nút điều khiển nhanh phía trên
            HStack {
                Button {
                    handleDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Spacer()

                if !playlistChannels.isEmpty {
                    Menu {
                        ForEach(playlistChannels.prefix(100)) { ch in
                            Button {
                                currentChannel = ch
                                store.recordRecent(channel: ch)
                            } label: {
                                HStack {
                                    Text(ch.name)
                                    if ch.id == currentChannel.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .onAppear {
            store.recordRecent(channel: currentChannel)
        }
        .onDisappear {
            handleDismiss()
        }
    }

    private func handleDismiss() {
        OrientationLockCoordinator.shared.rotateToPortrait()
        dismiss()
    }
}
