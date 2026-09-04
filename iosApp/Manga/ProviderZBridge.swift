import Foundation
import JavaScriptCore

/// Bridge kết nối và trích xuất dữ liệu truyện tranh từ Manga Add-ons / Provider-Z / REST API
public final class ProviderZBridge: @unchecked Sendable {
    public static let shared = ProviderZBridge()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - 1. Nạp danh sách truyện trang chủ theo Add-on
    public func fetchHomeManga(addon: MangaAddon? = nil) async -> [MangaItem] {
        let currentAddon = addon ?? MangaAddonManager.shared.activeAddon

        switch currentAddon.id {
        case "otruyen":
            let homeUrl = "\(currentAddon.baseUrl)/v1/api/danh-sach/truyen-moi?page=1"
            if let items = await fetchOtruyenList(from: homeUrl), !items.isEmpty {
                return items
            }
        case "cuutruyen":
            if let items = await fetchCuutruyenRecent(baseUrl: currentAddon.baseUrl), !items.isEmpty {
                return items
            }
        case "mangadex":
            if let items = await fetchMangadexPopular(baseUrl: currentAddon.baseUrl), !items.isEmpty {
                return items
            }
        default:
            // Custom Add-on / Provider-Z JSON
            if let items = await fetchCustomAddonList(addon: currentAddon), !items.isEmpty {
                return items
            }
        }

        // Fallback: Dữ liệu mẫu phong phú để thử nghiệm ngoại tuyến
        return mockHomeManga
    }

    // MARK: - 2. Tìm kiếm truyện theo Add-on
    public func searchManga(query: String, addon: MangaAddon? = nil) async -> [MangaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return await fetchHomeManga(addon: addon) }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        let currentAddon = addon ?? MangaAddonManager.shared.activeAddon

        switch currentAddon.id {
        case "otruyen":
            let searchUrl = "\(currentAddon.baseUrl)/v1/api/tim-kiem?keyword=\(encoded)"
            if let items = await fetchOtruyenList(from: searchUrl), !items.isEmpty {
                return items
            }
        case "cuutruyen":
            if let items = await fetchCuutruyenSearch(keyword: encoded, baseUrl: currentAddon.baseUrl), !items.isEmpty {
                return items
            }
        case "mangadex":
            if let items = await fetchMangadexSearch(keyword: encoded, baseUrl: currentAddon.baseUrl), !items.isEmpty {
                return items
            }
        default:
            break
        }

        // Tìm trong mock data nếu không có mạng
        return mockHomeManga.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - 3. Lấy chi tiết truyện và danh sách Chapter
    public func fetchDetail(for item: MangaItem, addon: MangaAddon? = nil) async -> MangaItem {
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

            // A. Cấu trúc OTruyen
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

            // B. Cấu trúc MangaDex / Provider-Z
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {
                var chaptersList: [MangaChapter] = []
                for ch in dataArr {
                    let chId = ch["id"] as? String ?? ""
                    let attr = ch["attributes"] as? [String: Any] ?? [:]
                    let chNum = attr["chapter"] as? String ?? ""
                    let chTitle = attr["title"] as? String ?? ""
                    let display = chNum.isEmpty ? "Chapter" : "Chương \(chNum)" + (chTitle.isEmpty ? "" : " - \(chTitle)")
                    chaptersList.append(
                        MangaChapter(
                            id: chId,
                            title: display,
                            chapterName: chNum,
                            url: "https://api.mangadex.org/at-home/server/\(chId)",
                            date: nil
                        )
                    )
                }
                if !chaptersList.isEmpty {
                    return MangaItem(
                        id: item.id,
                        title: item.title,
                        cover: item.cover,
                        posterUrl: item.posterUrl,
                        url: item.url,
                        description: item.description,
                        status: item.status,
                        genres: item.genres,
                        authors: item.authors,
                        chapters: chaptersList
                    )
                }
            }
        } catch {
            // Không ngắt mạch - chuyển sang fallback
        }

        return fallbackDetail(for: item)
    }

    // MARK: - 4. Lấy danh sách ảnh của 1 Chapter (getPages)
    public func fetchPages(chapterUrl: String, addon: MangaAddon? = nil) async -> [MangaPage] {
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

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // A. OTruyen format
                if let dataObj = json["data"] as? [String: Any],
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

                    if !pages.isEmpty { return pages }
                }

                // B. MangaDex format
                if let baseUrl = json["baseUrl"] as? String,
                   let chapterObj = json["chapter"] as? [String: Any],
                   let hash = chapterObj["hash"] as? String,
                   let dataImages = chapterObj["data"] as? [String] {
                    var pages: [MangaPage] = []
                    for (idx, filename) in dataImages.enumerated() {
                        let fullUrl = "\(baseUrl)/data/\(hash)/\(filename)"
                        pages.append(
                            MangaPage(index: idx, url: fullUrl, headers: ["Referer": "https://mangadex.org/"])
                        )
                    }
                    if !pages.isEmpty { return pages }
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

    // MARK: - Các hàm gọi API riêng cho từng nguồn (Private Helpers)
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

    private func fetchCuutruyenRecent(baseUrl: String) async -> [MangaItem]? {
        // Fallback demo CuuTruyen format
        return nil
    }

    private func fetchCuutruyenSearch(keyword: String, baseUrl: String) async -> [MangaItem]? {
        return nil
    }

    private func fetchMangadexPopular(baseUrl: String) async -> [MangaItem]? {
        let urlStr = "\(baseUrl)/manga?limit=20&includes[]=cover_art&order[followedCount]=desc&availableTranslatedLanguage[]=vi"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {

                return dataArr.compactMap { item -> MangaItem? in
                    guard let id = item["id"] as? String,
                          let attr = item["attributes"] as? [String: Any],
                          let titleObj = attr["title"] as? [String: String],
                          let title = titleObj.values.first else { return nil }

                    // Tìm cover filename từ relationships
                    var fileName: String?
                    if let rels = item["relationships"] as? [[String: Any]] {
                        for rel in rels {
                            if (rel["type"] as? String) == "cover_art",
                               let cAttr = rel["attributes"] as? [String: Any],
                               let f = cAttr["fileName"] as? String {
                                fileName = f
                                break
                            }
                        }
                    }

                    let coverUrl = fileName != nil
                        ? "https://uploads.mangadex.org/covers/\(id)/\(fileName!).256.jpg"
                        : "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=600"

                    let feedUrl = "\(baseUrl)/manga/\(id)/feed?translatedLanguage[]=vi&order[chapter]=desc&limit=100"

                    return MangaItem(
                        id: id,
                        title: title,
                        cover: coverUrl,
                        posterUrl: coverUrl,
                        url: feedUrl,
                        description: (attr["description"] as? [String: String])?.values.first,
                        status: attr["status"] as? String,
                        genres: ["MangaDex", "Manga"],
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

    private func fetchMangadexSearch(keyword: String, baseUrl: String) async -> [MangaItem]? {
        let urlStr = "\(baseUrl)/manga?title=\(keyword)&limit=20&includes[]=cover_art"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {
                return dataArr.compactMap { item -> MangaItem? in
                    guard let id = item["id"] as? String,
                          let attr = item["attributes"] as? [String: Any],
                          let titleObj = attr["title"] as? [String: String],
                          let title = titleObj.values.first else { return nil }

                    let coverUrl = "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=600"
                    let feedUrl = "\(baseUrl)/manga/\(id)/feed?order[chapter]=desc&limit=100"

                    return MangaItem(
                        id: id,
                        title: title,
                        cover: coverUrl,
                        posterUrl: coverUrl,
                        url: feedUrl,
                        description: nil,
                        status: attr["status"] as? String,
                        genres: ["MangaDex"],
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

    private func fetchCustomAddonList(addon: MangaAddon) async -> [MangaItem]? {
        guard let url = URL(string: addon.baseUrl) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let items = try? JSONDecoder().decode([MangaItem].self, from: data) {
                return items
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
            description: item.description ?? "Bộ truyện tranh đặc sắc, hấp dẫn được cập nhật từ Manga Add-on.",
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
            "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=1080",
            "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=1080",
            "https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=1080",
            "https://images.unsplash.com/photo-1563089145-599997674d42?w=1080",
            "https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1080"
        ]

        return (0..<count).map { idx in
            MangaPage(
                index: idx,
                url: sampleImages[idx % sampleImages.count],
                headers: nil
            )
        }
    }

    // MARK: - Mock Data Mẫu
    public var mockHomeManga: [MangaItem] {
        [
            MangaItem(
                id: "one-piece",
                title: "One Piece - Đảo Hải Tặc",
                cover: "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=600",
                posterUrl: "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=600",
                url: "mock://one-piece",
                description: "Hành trình tìm kiếm kho báu vĩ đại nhất thế giới của Monkey D. Luffy và băng Mũ Rơm.",
                status: "Đang tiến hành",
                genres: ["Hành Động", "Phiêu Lưu", "Hài Hước"],
                authors: ["Eiichiro Oda"],
                chapters: nil
            ),
            MangaItem(
                id: "solo-leveling",
                title: "Solo Leveling - Tôi Thăng Cấp Một Mình",
                cover: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600",
                posterUrl: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600",
                url: "mock://solo-leveling",
                description: "Thợ săn yếu nhất thế giới Sung Jin-Woo nhận được cơ hội thăng cấp không giới hạn.",
                status: "Hoàn thành",
                genres: ["Hành Động", "Giả Tưởng", "Trùng Sinh"],
                authors: ["Chugong", "DUBU"],
                chapters: nil
            ),
            MangaItem(
                id: "jujutsu-kaisen",
                title: "Jujutsu Kaisen - Chú Thuật Hồi Chiến",
                cover: "https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=600",
                posterUrl: "https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=600",
                url: "mock://jujutsu-kaisen",
                description: "Itadori Yuji nuốt ngón tay của Nguyền Vương Sukuna và bước vào thế giới chú thuật sư.",
                status: "Đang tiến hành",
                genres: ["Hành Động", "Kỳ Ảo", "Học Đường"],
                authors: ["Gege Akutami"],
                chapters: nil
            ),
            MangaItem(
                id: "frieren",
                title: "Sousou no Frieren - Pháp Sư Tiễn Táng",
                cover: "https://images.unsplash.com/photo-1563089145-599997674d42?w=600",
                posterUrl: "https://images.unsplash.com/photo-1563089145-599997674d42?w=600",
                url: "mock://frieren",
                description: "Hành trình sau khi đánh bại Ma Vương của nữ pháp sư elf bất tử Frieren.",
                status: "Đang tiến hành",
                genres: ["Phiêu Lưu", "Đời Thường", "Phép Thuật"],
                authors: ["Kanehito Yamada"],
                chapters: nil
            )
        ]
    }
}
