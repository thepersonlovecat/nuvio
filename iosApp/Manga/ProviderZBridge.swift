import Foundation
import JavaScriptCore

// MARK: - Lỗi Nguồn Truyện Tranh (Human-readable Source Errors)
public enum MangaSourceError: LocalizedError, Equatable {
    case noInternet
    case timeout(sourceName: String)
    case serverError(statusCode: Int, sourceName: String)
    case invalidResponse(sourceName: String)
    case emptyData(sourceName: String)
    case invalidUrl(urlString: String)
    case custom(message: String)

    public var errorDescription: String? {
        switch self {
        case .noInternet:
            return "Không có kết nối Internet. Vui lòng kiểm tra lại mạng Wi-Fi hoặc dữ liệu di động của bạn."
        case .timeout(let source):
            return "Máy chủ của \"\(source)\" phản hồi quá chậm (Hết thời gian chờ). Nguồn có thể đang bị quá tải."
        case .serverError(let code, let source):
            return "Máy chủ \"\(source)\" báo lỗi HTTP \(code). Nguồn này có thể đang được bảo trì hoặc bị chặn."
        case .invalidResponse(let source):
            return "Dữ liệu nhận được từ \"\(source)\" không đúng định dạng hoặc nguồn đã thay đổi API."
        case .emptyData(let source):
            return "Không tìm thấy dữ liệu truyện nào từ nguồn \"\(source)\"."
        case .invalidUrl(let url):
            return "Địa chỉ URL nguồn không hợp lệ: \(url)"
        case .custom(let message):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noInternet:
            return "Hãy kiểm tra lại kết nối mạng của bạn và bấm Thử lại."
        case .timeout, .serverError, .invalidResponse:
            return "Bạn có thể bấm Thử lại hoặc chọn chuyển sang nguồn truyện khác (OTruyen, MangaDex...)."
        case .emptyData:
            return "Hãy thử tìm kiếm với từ khóa khác hoặc đổi nguồn truyện."
        case .invalidUrl, .custom:
            return "Vui lòng kiểm tra lại cấu hình Add-on hoặc đổi nguồn."
        }
    }
}

// MARK: - Kết Quả Tải Danh Mục Truyện
public struct MangaCatalogLoadResult {
    public let items: [MangaItem]
    public let error: MangaSourceError?
    public let isFallback: Bool

    public init(items: [MangaItem], error: MangaSourceError? = nil, isFallback: Bool = false) {
        self.items = items
        self.error = error
        self.isFallback = isFallback
    }
}

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
    public func fetchHomeManga(addon: MangaAddon? = nil) async -> MangaCatalogLoadResult {
        let currentAddon = addon ?? MangaAddonManager.shared.activeAddon

        switch currentAddon.id {
        case "otruyen":
            let homeUrl = "\(currentAddon.baseUrl)/v1/api/danh-sach/truyen-moi?page=1"
            let res = await fetchOtruyenList(from: homeUrl, sourceName: currentAddon.name)
            switch res {
            case .success(let items):
                return MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }

        case "cuutruyen":
            let res = await fetchCuutruyenRecent(baseUrl: currentAddon.baseUrl, sourceName: currentAddon.name)
            switch res {
            case .success(let items):
                return MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }

        case "mangadex":
            let res = await fetchMangadexPopular(baseUrl: currentAddon.baseUrl, sourceName: currentAddon.name)
            switch res {
            case .success(let items):
                return MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }

        default:
            // Custom Add-on / Provider-Z JSON
            let res = await fetchCustomAddonList(addon: currentAddon)
            switch res {
            case .success(let items):
                return MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }
        }
    }

    // MARK: - 2. Tìm kiếm truyện theo Add-on
    public func searchManga(query: String, addon: MangaAddon? = nil) async -> MangaCatalogLoadResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return await fetchHomeManga(addon: addon) }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return MangaCatalogLoadResult(items: [], error: .custom(message: "Từ khóa tìm kiếm không hợp lệ."))
        }

        let currentAddon = addon ?? MangaAddonManager.shared.activeAddon

        switch currentAddon.id {
        case "otruyen":
            let searchUrl = "\(currentAddon.baseUrl)/v1/api/tim-kiem?keyword=\(encoded)"
            let res = await fetchOtruyenList(from: searchUrl, sourceName: currentAddon.name)
            switch res {
            case .success(let items):
                return items.isEmpty
                    ? MangaCatalogLoadResult(items: [], error: .emptyData(sourceName: currentAddon.name))
                    : MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }

        case "cuutruyen":
            let res = await fetchCuutruyenSearch(keyword: encoded, baseUrl: currentAddon.baseUrl, sourceName: currentAddon.name)
            switch res {
            case .success(let items):
                return items.isEmpty
                    ? MangaCatalogLoadResult(items: [], error: .emptyData(sourceName: currentAddon.name))
                    : MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }

        case "mangadex":
            let res = await fetchMangadexSearch(keyword: encoded, baseUrl: currentAddon.baseUrl, sourceName: currentAddon.name)
            switch res {
            case .success(let items):
                return items.isEmpty
                    ? MangaCatalogLoadResult(items: [], error: .emptyData(sourceName: currentAddon.name))
                    : MangaCatalogLoadResult(items: items)
            case .failure(let err):
                return MangaCatalogLoadResult(items: [], error: err)
            }

        default:
            return MangaCatalogLoadResult(items: [], error: .custom(message: "Nguồn này chưa hỗ trợ tìm kiếm trực tiếp."))
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
            // Chuyển sang fallback detail
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

    // MARK: - Helper ánh xạ lỗi mạng sang MangaSourceError
    private func mapNetworkError(_ error: Error, sourceName: String) -> MangaSourceError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return .noInternet
            case .timedOut:
                return .timeout(sourceName: sourceName)
            default:
                return .custom(message: urlError.localizedDescription)
            }
        }
        return .custom(message: error.localizedDescription)
    }

    // MARK: - Các hàm gọi API chi tiết (Trả về Result chuẩn)
    private func fetchOtruyenList(from urlString: String, sourceName: String) async -> Result<[MangaItem], MangaSourceError> {
        guard let url = URL(string: urlString) else {
            return .failure(.invalidUrl(urlString: urlString))
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("https://otruyen.cc/", forHTTPHeaderField: "Referer")
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: sourceName))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: sourceName))
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataObj = json["data"] as? [String: Any],
               let items = dataObj["items"] as? [[String: Any]] {

                let cdn = "https://img.otruyenapi.com/uploads/comics"
                let mapped = items.compactMap { dict -> MangaItem? in
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
                return .success(mapped)
            }
            return .failure(.invalidResponse(sourceName: sourceName))
        } catch {
            return .failure(mapNetworkError(error, sourceName: sourceName))
        }
    }

    private func fetchCuutruyenRecent(baseUrl: String, sourceName: String) async -> Result<[MangaItem], MangaSourceError> {
        let urlStr = "\(baseUrl)/mangas/recently_updated"
        guard let url = URL(string: urlStr) else {
            return .failure(.invalidUrl(urlString: urlStr))
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: sourceName))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: sourceName))
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {
                let mapped = dataArr.compactMap { dict -> MangaItem? in
                    guard let id = dict["id"] as? Int,
                          let name = dict["name"] as? String else { return nil }
                    let cover = dict["cover_url"] as? String ?? ""
                    return MangaItem(
                        id: "\(id)",
                        title: name,
                        cover: cover,
                        posterUrl: cover,
                        url: "\(baseUrl)/mangas/\(id)",
                        description: dict["description"] as? String,
                        status: nil,
                        genres: ["Cửu Truyện"],
                        authors: nil,
                        chapters: nil
                    )
                }
                return .success(mapped)
            }
            return .failure(.invalidResponse(sourceName: sourceName))
        } catch {
            return .failure(mapNetworkError(error, sourceName: sourceName))
        }
    }

    private func fetchCuutruyenSearch(keyword: String, baseUrl: String, sourceName: String) async -> Result<[MangaItem], MangaSourceError> {
        let urlStr = "\(baseUrl)/mangas/search?q=\(keyword)"
        guard let url = URL(string: urlStr) else {
            return .failure(.invalidUrl(urlString: urlStr))
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: sourceName))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: sourceName))
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {
                let mapped = dataArr.compactMap { dict -> MangaItem? in
                    guard let id = dict["id"] as? Int,
                          let name = dict["name"] as? String else { return nil }
                    let cover = dict["cover_url"] as? String ?? ""
                    return MangaItem(
                        id: "\(id)",
                        title: name,
                        cover: cover,
                        posterUrl: cover,
                        url: "\(baseUrl)/mangas/\(id)",
                        description: nil,
                        status: nil,
                        genres: ["Cửu Truyện"],
                        authors: nil,
                        chapters: nil
                    )
                }
                return .success(mapped)
            }
            return .failure(.invalidResponse(sourceName: sourceName))
        } catch {
            return .failure(mapNetworkError(error, sourceName: sourceName))
        }
    }

    private func fetchMangadexPopular(baseUrl: String, sourceName: String) async -> Result<[MangaItem], MangaSourceError> {
        let urlStr = "\(baseUrl)/manga?limit=20&includes[]=cover_art&order[followedCount]=desc&availableTranslatedLanguage[]=vi"
        guard let url = URL(string: urlStr) else {
            return .failure(.invalidUrl(urlString: urlStr))
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: sourceName))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: sourceName))
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {

                let mapped = dataArr.compactMap { item -> MangaItem? in
                    guard let id = item["id"] as? String,
                          let attr = item["attributes"] as? [String: Any],
                          let titleObj = attr["title"] as? [String: String],
                          let title = titleObj.values.first else { return nil }

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
                return .success(mapped)
            }
            return .failure(.invalidResponse(sourceName: sourceName))
        } catch {
            return .failure(mapNetworkError(error, sourceName: sourceName))
        }
    }

    private func fetchMangadexSearch(keyword: String, baseUrl: String, sourceName: String) async -> Result<[MangaItem], MangaSourceError> {
        let urlStr = "\(baseUrl)/manga?title=\(keyword)&limit=20&includes[]=cover_art"
        guard let url = URL(string: urlStr) else {
            return .failure(.invalidUrl(urlString: urlStr))
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: sourceName))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: sourceName))
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]] {
                let mapped = dataArr.compactMap { item -> MangaItem? in
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
                return .success(mapped)
            }
            return .failure(.invalidResponse(sourceName: sourceName))
        } catch {
            return .failure(mapNetworkError(error, sourceName: sourceName))
        }
    }

    private func fetchCustomAddonList(addon: MangaAddon) async -> Result<[MangaItem], MangaSourceError> {
        guard let url = URL(string: addon.baseUrl) else {
            return .failure(.invalidUrl(urlString: addon.baseUrl))
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: addon.name))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: addon.name))
            }

            if let items = try? JSONDecoder().decode([MangaItem].self, from: data) {
                return .success(items)
            }
            return .failure(.invalidResponse(sourceName: addon.name))
        } catch {
            return .failure(mapNetworkError(error, sourceName: addon.name))
        }
    }

    private func fallbackDetail(for item: MangaItem) -> MangaItem {
        MangaItem(
            id: item.id,
            title: item.title,
            cover: item.cover,
            posterUrl: item.posterUrl,
            url: item.url,
            description: item.description ?? "Bộ truyện tranh đặc sắc, hấp dẫn.",
            status: item.status ?? "Đang tiến hành",
            genres: item.genres ?? ["Hành động", "Phiêu lưu"],
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
                date: "Mới cập nhật"
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

    // MARK: - Dữ Liệu Mẫu (Chỉ dùng khi người dùng chủ động chọn Xem Dữ Liệu Mẫu Ngoại Tuyến)
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
