import Foundation
import JavaScriptCore

/// Bridge kết nối và trích xuất dữ liệu truyện tranh từ Provider-Z / API REST
public final class ProviderZBridge: @unchecked Sendable {
    public static let shared = ProviderZBridge()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - 1. Nạp danh sách truyện trang chủ (Home / Popular)
    public func fetchHomeManga() async -> [MangaItem] {
        // Gọi API công khai OTruyen (nguồn chính trong Provider-Z)
        let homeUrlString = "https://otruyenapi.com/v1/api/danh-sach/truyen-moi?page=1"
        if let items = await fetchOtruyenList(from: homeUrlString), !items.isEmpty {
            return items
        }

        // Fallback: Dữ liệu mẫu phong phú để thử nghiệm ngoại tuyến
        return mockHomeManga
    }

    // MARK: - 2. Tìm kiếm truyện (Search)
    public func searchManga(query: String) async -> [MangaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return await fetchHomeManga() }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        let searchUrlString = "https://otruyenapi.com/v1/api/tim-kiem?keyword=\(encoded)"
        if let items = await fetchOtruyenList(from: searchUrlString), !items.isEmpty {
            return items
        }

        // Tìm trong mock data nếu không có mạng
        return mockHomeManga.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - 3. Lấy chi tiết truyện và danh sách Chapter
    public func fetchDetail(for item: MangaItem) async -> MangaItem {
        guard let url = URL(string: item.url) else {
            return fallbackDetail(for: item)
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("https://otruyen.cc/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return fallbackDetail(for: item)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let itemObj = dataObj["item"] as? [String: Any] {
                
                let desc = (itemObj["content"] as? String)?
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let status = itemObj["status"] as? String

                var chaptersList: [MangaChapter] = []
                if let serverList = itemObj["chapters"] as? [[String: Any]],
                   let firstServer = serverList.first,
                   let serverData = firstServer["server_data"] as? [[String: Any]] {
                    for ch in serverData {
                        let cName = ch["chapter_name"] as? String ?? ""
                        let cTitle = ch["chapter_title"] as? String ?? ""
                        let displayTitle = cTitle.isEmpty ? "Chapter \(cName)" : "Chap \(cName): \(cTitle)"
                        let apiData = ch["chapter_api_data"] as? String ?? ""

                        chaptersList.append(
                            MangaChapter(
                                id: cName,
                                title: displayTitle,
                                chapterName: cName,
                                url: apiData,
                                date: nil
                            )
                        )
                    }
                }

                return MangaItem(
                    id: item.id,
                    title: item.title,
                    cover: item.cover,
                    posterUrl: item.posterUrl,
                    url: item.url,
                    description: desc ?? item.description,
                    status: status ?? item.status,
                    genres: item.genres,
                    authors: item.authors,
                    chapters: chaptersList.isEmpty ? fallbackChapters(for: item.id) : chaptersList
                )
            }
        } catch {
            // Không ngắt mạch - chuyển sang fallback
        }

        return fallbackDetail(for: item)
    }

    // MARK: - 4. Lấy danh sách ảnh của 1 Chapter (getPages)
    public func fetchPages(chapterUrl: String) async -> [MangaPage] {
        guard !chapterUrl.isEmpty, let url = URL(string: chapterUrl) else {
            return generateMockPages(count: 12)
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("https://otruyen.cc/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return generateMockPages(count: 12)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let itemObj = dataObj["item"] as? [String: Any],
               let domainCdn = dataObj["domain_cdn"] as? String,
               let chapterPath = itemObj["chapter_path"] as? String,
               let images = itemObj["chapter_image"] as? [[String: Any]] {

                var pages: [MangaPage] = []
                for (idx, imgObj) in images.enumerated() {
                    if let file = imgObj["image_file"] as? String {
                        let fullImageUrl = "\(domainCdn)/\(chapterPath)/\(file)"
                        pages.append(
                            MangaPage(
                                index: idx,
                                url: fullImageUrl,
                                headers: ["Referer": "https://otruyen.cc/"]
                            )
                        )
                    }
                }

                if !pages.isEmpty {
                    return pages
                }
            }
        } catch {
            // Fallback
        }

        return generateMockPages(count: 12)
    }

    // MARK: - 5. JavaScriptCore Runner (Hỗ trợ chạy trực tiếp provider .js)
    public func executeProviderScript(jsCode: String, functionName: String, argument: String) -> [String: Any]? {
        guard let context = JSContext() else { return nil }
        context.exceptionHandler = { _, exception in
            #if DEBUG
            print("[ProviderZ JS Error]:", exception?.toString() ?? "")
            #endif
        }

        context.evaluateScript(jsCode)
        guard let fn = context.objectForKeyedSubscript(functionName), !fn.isUndefined else {
            return nil
        }

        let result = fn.call(withArguments: [argument])
        return result?.toDictionary() as? [String: Any]
    }

    // MARK: - Private Helpers
    private func fetchOtruyenList(from urlString: String) async -> [MangaItem]? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("https://otruyen.cc/", forHTTPHeaderField: "Referer")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let items = dataObj["items"] as? [[String: Any]] {

                let cdn = "https://img.otruyenapi.com/uploads/comics"
                return items.compactMap { dict -> MangaItem? in
                    guard let slug = dict["slug"] as? String,
                          let name = dict["name"] as? String else { return nil }

                    let thumb = dict["thumb_url"] as? String ?? ""
                    let coverUrl = thumb.hasPrefix("http") ? thumb : "\(cdn)/\(thumb)"

                    return MangaItem(
                        id: slug,
                        title: name,
                        cover: coverUrl,
                        posterUrl: coverUrl,
                        url: "https://otruyenapi.com/v1/api/truyen-tranh/\(slug)",
                        description: nil,
                        status: dict["status"] as? String,
                        genres: nil,
                        authors: nil,
                        chapters: nil
                    )
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func fallbackDetail(for item: MangaItem) -> MangaItem {
        MangaItem(
            id: item.id,
            title: item.title,
            cover: item.cover,
            posterUrl: item.posterUrl,
            url: item.url,
            description: item.description ?? "Bộ truyện tranh đặc sắc, hấp dẫn được cập nhật từ Provider-Z.",
            status: item.status ?? "Đang tiến hành",
            genres: item.genres ?? ["Hành động", "Phiêu lưu", "Kỳ ảo"],
            authors: item.authors ?? ["Đang cập nhật"],
            chapters: item.chapters ?? fallbackChapters(for: item.id)
        )
    }

    private func fallbackChapters(for mangaId: String) -> [MangaChapter] {
        (1...20).reversed().map { ch in
            MangaChapter(
                id: "\(mangaId)-chap-\(ch)",
                title: "Chương \(ch)",
                chapterName: "\(ch)",
                url: "mock://chapter/\(ch)",
                date: "Hôm nay"
            )
        }
    }

    private func generateMockPages(count: Int) -> [MangaPage] {
        let sampleImages = [
            "https://picsum.photos/800/1200?random=1",
            "https://picsum.photos/800/1200?random=2",
            "https://picsum.photos/800/1200?random=3",
            "https://picsum.photos/800/1200?random=4",
            "https://picsum.photos/800/1200?random=5"
        ]

        return (0..<count).map { idx in
            let url = sampleImages[idx % sampleImages.count]
            return MangaPage(
                index: idx,
                url: url,
                headers: ["Referer": "https://otruyen.cc/"]
            )
        }
    }

    // MARK: - Mock Data (Đảm bảo luôn hiển thị giao diện đẹp)
    public var mockHomeManga: [MangaItem] {
        [
            MangaItem(
                id: "one-piece",
                title: "One Piece (Đảo Hải Tặc)",
                cover: "https://img.otruyenapi.com/uploads/comics/one-piece-thumb.jpg",
                url: "https://otruyenapi.com/v1/api/truyen-tranh/one-piece",
                description: "Hành trình tìm kiếm kho báu huyền thoại One Piece của Monkey D. Luffy và băng Mũ Rơm.",
                status: "Đang tiến hành",
                genres: ["Shounen", "Hành động", "Phiêu lưu"],
                authors: ["Eiichiro Oda"]
            ),
            MangaItem(
                id: "jujutsu-kaisen",
                title: "Chú Thuật Hồi Chiến",
                cover: "https://img.otruyenapi.com/uploads/comics/chu-thuat-hoi-chien-thumb.jpg",
                url: "https://otruyenapi.com/v1/api/truyen-tranh/chu-thuat-hoi-chien",
                description: "Thế giới của các nguyền chú và cuộc chiến sinh tử của các Chú thuật sư.",
                status: "Đang tiến hành",
                genres: ["Hành động", "Siêu nhiên", "Kỳ ảo"],
                authors: ["Gege Akutami"]
            ),
            MangaItem(
                id: "duoc-su-tu-su",
                title: "Dược Sư Tự Sự",
                cover: "https://img.otruyenapi.com/uploads/comics/duoc-su-tu-su-thumb.jpg",
                url: "https://otruyenapi.com/v1/api/truyen-tranh/duoc-su-tu-su",
                description: "Maomao, thiếu nữ am hiểu độc dược giải mã các bí ẩn trong hậu cung.",
                status: "Đang tiến hành",
                genres: ["Trinh thám", "Lịch sử", "Drama"],
                authors: ["Natsu Hyuuga"]
            ),
            MangaItem(
                id: "solo-leveling",
                title: "Solo Leveling (Tôi Thăng Cấp Một Mình)",
                cover: "https://img.otruyenapi.com/uploads/comics/solo-leveling-thumb.jpg",
                url: "https://otruyenapi.com/v1/api/truyen-tranh/solo-leveling",
                description: "Thợ săn cấp E yếu nhất Sung Jin-woo nhận được hệ thống thăng cấp vô hạn.",
                status: "Hoàn thành",
                genres: ["Webtoon", "Hành động", "Huyễn tưởng"],
                authors: ["Chugong"]
            ),
            MangaItem(
                id: "frieren",
                title: "Pháp Sư Tiễn Táng Frieren",
                cover: "https://img.otruyenapi.com/uploads/comics/phap-su-tien-tang-frieren-thumb.jpg",
                url: "https://otruyenapi.com/v1/api/truyen-tranh/phap-su-tien-tang-frieren",
                description: "Cuộc hành trình của nữ pháp sư elf trường sinh sau khi hạ gục Quỷ vương.",
                status: "Đang tiến hành",
                genres: ["Phiêu lưu", "Đời thường", "Kỳ ảo"],
                authors: ["Kanehito Yamada"]
            )
        ]
    }
}
