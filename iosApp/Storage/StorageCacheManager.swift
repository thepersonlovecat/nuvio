import Foundation
import Combine
import UIKit

@MainActor
public final class StorageCacheManager: ObservableObject {

    public static let shared = StorageCacheManager()

    @Published public var mangaCacheBytes: Int64 = 0
    @Published public var videoCacheBytes: Int64 = 0
    @Published public var systemCacheBytes: Int64 = 0
    @Published public var totalCacheBytes: Int64 = 0

    @Published public var isCalculating: Bool = false
    @Published public var isCleaning: Bool = false
    @Published public var lastCleanedAt: Date? = nil

    private init() {
        Task {
            await calculateSizes()
        }
    }

    public var totalFormatted: String {
        formatBytes(totalCacheBytes)
    }

    public var mangaFormatted: String {
        formatBytes(mangaCacheBytes)
    }

    public var videoFormatted: String {
        formatBytes(videoCacheBytes)
    }

    public var systemFormatted: String {
        formatBytes(systemCacheBytes)
    }

    // MARK: - Calculations

    public func calculateSizes() async {
        isCalculating = true

        let fileManager = FileManager.default
        let cachesUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())

        var mangaBytes: Int64 = 0
        var videoBytes: Int64 = 0
        var sysBytes: Int64 = 0

        // 1. Quét Caches Directory
        if let enumerator = fileManager.enumerator(at: cachesUrl, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileUrl as URL in enumerator {
                guard let resourceValues = try? fileUrl.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                      resourceValues.isDirectory != true,
                      let fileSize = resourceValues.fileSize else {
                    continue
                }

                let path = fileUrl.path.lowercased()
                if path.contains("manga") || path.contains("img") || path.contains("image") {
                    mangaBytes += Int64(fileSize)
                } else if path.contains("mpv") || path.contains("video") || path.contains("stream") || path.contains("hls") || path.contains("dash") {
                    videoBytes += Int64(fileSize)
                } else {
                    sysBytes += Int64(fileSize)
                }
            }
        }

        // 2. Quét Temp Directory (Nơi MPV và livestream lưu buffer tạm)
        if let tempEnumerator = fileManager.enumerator(at: tempUrl, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileUrl as URL in tempEnumerator {
                guard let resourceValues = try? fileUrl.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                      resourceValues.isDirectory != true,
                      let fileSize = resourceValues.fileSize else {
                    continue
                }

                videoBytes += Int64(fileSize)
            }
        }

        // 3. Cộng thêm URLCache của MangaImageLoader nếu có
        let urlCacheManga = URLCache.shared.currentDiskUsage
        if mangaBytes == 0 && urlCacheManga > 0 {
            mangaBytes = Int64(urlCacheManga)
        }

        self.mangaCacheBytes = mangaBytes
        self.videoCacheBytes = videoBytes
        self.systemCacheBytes = sysBytes
        self.totalCacheBytes = mangaBytes + videoBytes + sysBytes
        self.isCalculating = false
    }

    // MARK: - Cleaning Actions

    public func clearAll() async {
        isCleaning = true

        // 1. Dọn cache Manga
        MangaImageLoader.shared.clearCache()

        // 2. Dọn URLCache hệ thống
        URLCache.shared.removeAllCachedResponses()

        // 3. Dọn thư mục Caches
        let fileManager = FileManager.default
        let cachesUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if let items = try? fileManager.contentsOfDirectory(at: cachesUrl, includingPropertiesForKeys: nil) {
            for item in items {
                try? fileManager.removeItem(at: item)
            }
        }

        // 4. Dọn thư mục Tạm (NSTemporaryDirectory)
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        if let tempItems = try? fileManager.contentsOfDirectory(at: tempUrl, includingPropertiesForKeys: nil) {
            for item in tempItems {
                try? fileManager.removeItem(at: item)
            }
        }

        // Haptic feedback thành công
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        try? await Task.sleep(nanoseconds: 500_000_000)
        lastCleanedAt = Date()
        await calculateSizes()
        isCleaning = false
    }

    public func clearManga() async {
        isCleaning = true
        MangaImageLoader.shared.clearCache()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await calculateSizes()
        isCleaning = false
    }

    public func clearVideoAndIPTV() async {
        isCleaning = true
        let fileManager = FileManager.default
        let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory())
        if let tempItems = try? fileManager.contentsOfDirectory(at: tempUrl, includingPropertiesForKeys: nil) {
            for item in tempItems {
                try? fileManager.removeItem(at: item)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await calculateSizes()
        isCleaning = false
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
