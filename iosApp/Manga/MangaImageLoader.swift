import Foundation
import SwiftUI
import UIKit

/// Bộ tải & cache ảnh truyện dùng chung cho toàn bộ tính năng Truyện.
///
/// Vì sao không dùng `AsyncImage` mặc định:
/// - `AsyncImage` không gửi kèm header (ví dụ `Referer`) nên nhiều CDN truyện từ chối tải ảnh.
/// - Không có cache thật sự: cuộn lên rồi cuộn xuống phải tải lại từ đầu, tốn dữ liệu di động.
/// - Không có cơ chế thử lại khi một trang tải lỗi.
final class MangaImageLoader {
    static let shared = MangaImageLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [String: Task<UIImage, Error>] = [:]
    private let lock = NSLock()

    private init() {
        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 256 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: nil
        )
        session = URLSession(configuration: config)
    }

    func image(for page: MangaPage) async throws -> UIImage {
        try await image(urlString: page.url, headers: page.headers)
    }

    func image(urlString: String, headers: [String: String]? = nil) async throws -> UIImage {
        let key = urlString as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // Gom các request trùng nhau: nhiều view cùng hỏi 1 ảnh chỉ tạo 1 request mạng.
        lock.lock()
        if let existing = inFlight[urlString] {
            lock.unlock()
            return try await existing.value
        }
        guard let url = URL(string: urlString) else {
            lock.unlock()
            throw URLError(.badURL)
        }
        let task = Task<UIImage, Error> { [session, memoryCache] in
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            memoryCache.setObject(image, forKey: key, cost: data.count)
            return image
        }
        inFlight[urlString] = task
        lock.unlock()

        defer {
            lock.lock()
            inFlight[urlString] = nil
            lock.unlock()
        }
        return try await task.value
    }

    /// Tải trước các trang sắp đọc tới để khi cuộn/sang trang không phải chờ.
    func prefetch(_ pages: [MangaPage]) {
        for page in pages {
            let key = page.url as NSString
            if memoryCache.object(forKey: key) != nil { continue }
            Task.detached(priority: .utility) { [weak self] in
                _ = try? await self?.image(for: page)
            }
        }
    }
}

// MARK: - MangaAsyncImage (View ảnh có cache + nút thử lại)

/// Ảnh tải bất đồng bộ qua `MangaImageLoader`, tự hủy tải khi view biến mất,
/// và cho phép người dùng bấm thử lại khi lỗi.
struct MangaAsyncImage<Success: View, Placeholder: View, Failure: View>: View {
    let urlString: String
    let headers: [String: String]?
    @ViewBuilder let success: (UIImage) -> Success
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: (@escaping () -> Void) -> Failure

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var attempt = 0

    init(
        urlString: String,
        headers: [String: String]? = nil,
        @ViewBuilder success: @escaping (UIImage) -> Success,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping (@escaping () -> Void) -> Failure
    ) {
        self.urlString = urlString
        self.headers = headers
        self.success = success
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if let image {
                success(image)
            } else if didFail {
                failure {
                    didFail = false
                    attempt += 1
                }
            } else {
                placeholder()
            }
        }
        .task(id: attempt) {
            guard image == nil else { return }
            didFail = false
            do {
                let loaded = try await MangaImageLoader.shared.image(urlString: urlString, headers: headers)
                guard !Task.isCancelled else { return }
                image = loaded
            } catch {
                guard !Task.isCancelled else { return }
                didFail = true
            }
        }
    }
}

// MARK: - MangaCoverImageView (Ảnh bìa truyện dùng trong Catalog / Thư viện / Lịch sử)

struct MangaCoverImageView: View {
    let urlString: String

    var body: some View {
        MangaAsyncImage(urlString: urlString) { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color(red: 0.12, green: 0.12, blue: 0.12)
                ProgressView().tint(.white)
            }
        } failure: { retry in
            ZStack {
                Color(red: 0.12, green: 0.12, blue: 0.12)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.gray)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: retry)
            .accessibilityLabel("Ảnh bìa tải lỗi, chạm để thử lại")
        }
    }
}
