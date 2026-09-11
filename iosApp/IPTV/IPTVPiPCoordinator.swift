import Foundation
import AVKit
import UIKit
import Combine

@MainActor
public final class IPTVPiPCoordinator: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {

    public static let shared = IPTVPiPCoordinator()

    @Published public var isPiPActive: Bool = false
    @Published public var isPiPPossible: Bool = false
    @Published public var isPiPSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()

    private var pipController: AVPictureInPictureController?
    private var pipVideoCallVC: AVPictureInPictureVideoCallViewController?
    private var targetView: UIView?

    private override init() {
        super.init()
    }

    public func configure(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        self.targetView = sourceView

        // Bật Audio Session nền để giữ luồng phát khi PiP
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PiP] Audio session setup error: \(error.localizedDescription)")
        }

        if #available(iOS 15.0, *) {
            let videoCallVC = AVPictureInPictureVideoCallViewController()
            videoCallVC.preferredContentSize = CGSize(width: 16, height: 9)
            self.pipVideoCallVC = videoCallVC

            let contentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: sourceView,
                contentViewController: videoCallVC
            )

            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            self.pipController = controller
            self.isPiPPossible = controller.isPictureInPicturePossible
        }
    }

    public func startPiP() {
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        pip.startPictureInPicture()
    }

    public func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    public func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate

    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        isPiPActive = false
        print("[PiP] Failed to start PiP: \(error.localizedDescription)")
    }
}
