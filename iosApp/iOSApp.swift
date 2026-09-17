import SwiftUI
import ComposeApp

@main
struct iOSApp: App {
    @UIApplicationDelegateAdaptor(OrientationLockAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if url.isFileURL {
                        let ext = url.pathExtension.lowercased()
                        if ext == "m3u" || ext == "m3u8" || ext == "txt" || ext.isEmpty {
                            Task {
                                _ = await IPTVPlaylistStore.shared.addLocalFilePlaylist(
                                    name: url.deletingPathExtension().lastPathComponent,
                                    sourceURL: url
                                )
                            }
                            return
                        }
                    }
                    AppUrlBridgeKt.handleAppUrl(url: url.absoluteString)
                }
        }
    }
}
