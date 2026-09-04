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
    case noAddonInstalled
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
        case .noAddonInstalled:
            return "Bạn chưa cài đặt nguồn truyện (Add-on) nào."
        case .custom(let message):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noInternet:
            return "Hãy kiểm tra lại kết nối mạng của bạn và bấm Thử lại."
        case .timeout, .serverError, .invalidResponse:
            return "Bạn có thể bấm Thử lại hoặc chọn chuyển sang nguồn truyện khác."
        case .emptyData:
            return "Hãy thử tìm kiếm với từ khóa khác hoặc đổi nguồn truyện."
        case .noAddonInstalled:
            return "Bấm \"Quản lý Add-on\" và dán link manifest.json của nguồn truyện để cài đặt."
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
    /// Nguồn có còn trang dữ liệu tiếp theo để tải thêm (infinite scroll) hay không.
    public let hasMorePages: Bool

    public init(items: [MangaItem], error: MangaSourceError? = nil, isFallback: Bool = false, hasMorePages: Bool = false) {
        self.items = items
        self.error = error
        self.isFallback = isFallback
        self.hasMorePages = hasMorePages
    }
}

/// DTO "mềm" cho chi tiết truyện: mọi trường đều optional,
/// trường nào thiếu sẽ giữ nguyên dữ liệu gốc đã có của item.
private struct MangaDetailPayload: Decodable {
    let id: String?
    let title: String?
    let cover: String?
    let posterUrl: String?
    let url: String?
    let description: String?
    let status: String?
    let genres: [String]?
    let authors: [String]?
    let chapters: [MangaChapter]?

    enum CodingKeys: String, CodingKey {
        case id, title, cover, url, description, status, genres, authors, chapters
        case posterUrl = "posterUrl"
        case posterUrlSnake = "poster_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
            ?? c.decodeIfPresent(String.self, forKey: .posterUrlSnake)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        genres = try c.decodeIfPresent([String].self, forKey: .genres)
        authors = try c.decodeIfPresent([String].self, forKey: .authors)
        chapters = try c.decodeIfPresent([MangaChapter].self, forKey: .chapters)
    }

    func merged(into item: MangaItem) -> MangaItem {
        MangaItem(
            id: id ?? item.id,
            title: title ?? item.title,
            cover: cover ?? item.cover,
            posterUrl: posterUrl ?? item.posterUrl,
            url: url ?? item.url,
            description: description ?? item.description,
            status: status ?? item.status,
            genres: genres ?? item.genres,
            authors: authors ?? item.authors,
            chapters: chapters ?? item.chapters
        )
    }
}

/// Bridge kết nối dữ liệu truyện tranh từ Manga Add-on do người dùng cài đặt.
///
/// Hoàn toàn generic - không chèn cứng bất kỳ nguồn nào. Mọi hành vi được
/// điều khiển bởi file manifest.json của Add-on (xem MANGA_ADDON_GUIDE.md):
/// - `baseUrl`: endpoint mặc định cho danh sách trang chủ.
/// - `endpoints.home/search/detail/chapter`: mẫu URL với biến {query}, {id}, {page}.
/// - `headers`: header HTTP (ví dụ Referer) gửi kèm mọi request của nguồn.
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
    public func fetchHomeManga(addon: MangaAddon? = nil, page: Int = 1) async -> MangaCatalogLoadResult {
        guard let currentAddon = addon ?? MangaAddonManager.shared.activeAddon else {
            return MangaCatalogLoadResult(items: [], error: .noAddonInstalled)
        }

        let template = currentAddon.endpoints?.home ?? currentAddon.baseUrl
        guard let urlString = resolveEndpoint(template, addon: currentAddon, values: ["page": "\(max(1, page))"]),
              let url = URL(string: urlString) else {
            return MangaCatalogLoadResult(items: [], error: .invalidUrl(urlString: template))
        }

        let res = await fetchMangaList(from: url, addon: currentAddon)
        switch res {
        case .success(let items):
            // Chỉ hỗ trợ tải thêm trang khi nguồn khai báo biến {page} trong manifest
            let hasMore = (currentAddon.endpoints?.home?.contains("{page}") ?? false) && !items.isEmpty
            return MangaCatalogLoadResult(items: items, hasMorePages: hasMore)
        case .failure(let err):
            return MangaCatalogLoadResult(items: [], error: err)
        }
    }

    // MARK: - 2. Tìm kiếm truyện theo Add-on
    public func searchManga(query: String, addon: MangaAddon? = nil, page: Int = 1) async -> MangaCatalogLoadResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return await fetchHomeManga(addon: addon, page: page) }

        guard let currentAddon = addon ?? MangaAddonManager.shared.activeAddon else {
            return MangaCatalogLoadResult(items: [], error: .noAddonInstalled)
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return MangaCatalogLoadResult(items: [], error: .custom(message: "Từ khóa tìm kiếm không hợp lệ."))
        }

        guard let template = currentAddon.endpoints?.search else {
            return MangaCatalogLoadResult(
                items: [],
                error: .custom(message: "Nguồn \"\(currentAddon.name)\" chưa khai báo endpoint tìm kiếm (search) trong manifest.")
            )
        }

        guard let urlString = resolveEndpoint(template, addon: currentAddon, values: ["query": encoded, "page": "\(max(1, page))"]),
              let url = URL(string: urlString) else {
            return MangaCatalogLoadResult(items: [], error: .invalidUrl(urlString: template))
        }

        let res = await fetchMangaList(from: url, addon: currentAddon)
        switch res {
        case .success(let items):
            if items.isEmpty {
                return page > 1
                    ? MangaCatalogLoadResult(items: [], hasMorePages: false)
                    : MangaCatalogLoadResult(items: [], error: .emptyData(sourceName: currentAddon.name))
            }
            let hasMore = template.contains("{page}")
            return MangaCatalogLoadResult(items: items, hasMorePages: hasMore)
        case .failure(let err):
            return MangaCatalogLoadResult(items: [], error: err)
        }
    }

    // MARK: - 3. Lấy chi tiết truyện và danh sách Chapter
    /// Trường nào nguồn không trả về sẽ giữ nguyên dữ liệu gốc của item;
    /// không tải được thì trả về item gốc (không bịa dữ liệu giả).
    public func fetchDetail(for item: MangaItem, addon: MangaAddon? = nil) async -> MangaItem {
        let currentAddon = addon ?? MangaAddonManager.shared.activeAddon

        var urlString = item.url
        if let addon = currentAddon,
           let template = addon.endpoints?.detail,
           let resolved = resolveEndpoint(template, addon: addon, values: ["id": item.id]) {
            urlString = resolved
        }

        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            return item
        }

        do {
            let (data, response) = try await session.data(for: makeRequest(url: url, addon: currentAddon))
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return item
            }

            // A. Object chi tiết nằm trực tiếp ở root (chuẩn trong MANGA_ADDON_GUIDE)
            if let payload = try? JSONDecoder().decode(MangaDetailPayload.self, from: data) {
                return payload.merged(into: item)
            }

            // B. Object chi tiết nằm trong wrapper {"data": {...}} hoặc {"item": {...}}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for wrapperKey in ["data", "item"] {
                    if let nested = json[wrapperKey],
                       JSONSerialization.isValidJSONObject(nested),
                       let nestedData = try? JSONSerialization.data(withJSONObject: nested),
                       let payload = try? JSONDecoder().decode(MangaDetailPayload.self, from: nestedData) {
                        return payload.merged(into: item)
                    }
                }
            }
        } catch {
            // Lỗi mạng: giữ nguyên dữ liệu gốc
        }

        return item
    }

    // MARK: - 4. Lấy danh sách ảnh của 1 Chapter (getPages)
    /// Trả về mảng rỗng khi lỗi để Reader hiển thị màn hình lỗi rõ ràng kèm nút Thử lại,
    /// tuyệt đối không trả về dữ liệu giả.
    public func fetchPages(chapterUrl: String, addon: MangaAddon? = nil) async -> [MangaPage] {
        let currentAddon = addon ?? MangaAddonManager.shared.activeAddon
        guard !chapterUrl.isEmpty, let url = URL(string: chapterUrl) else {
            return []
        }

        do {
            let (data, response) = try await session.data(for: makeRequest(url: url, addon: currentAddon))
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return []
            }

            if let json = try? JSONSerialization.jsonObject(with: data) {
                // A. {"pages": [...]} - mảng chuỗi URL hoặc object {url, headers}
                if let dict = json as? [String: Any], let pages = dict["pages"] {
                    let parsed = parsePageArray(pages, fallbackHeaders: currentAddon?.headers)
                    if !parsed.isEmpty { return parsed }
                }

                // B. Mảng URL nằm trực tiếp ở root: ["https://.../01.jpg", ...]
                if let array = json as? [Any] {
                    let parsed = parsePageArray(array, fallbackHeaders: currentAddon?.headers)
                    if !parsed.isEmpty { return parsed }
                }

                // C. Cấu trúc CDN trong guide:
                // {"data": {"domain_cdn": "...", "item": {"chapter_path": "...", "chapter_image": [{"image_file": "..."}]}}}
                if let dict = json as? [String: Any],
                   let dataObj = dict["data"] as? [String: Any],
                   let itemObj = dataObj["item"] as? [String: Any],
                   let domainCdn = dataObj["domain_cdn"] as? String,
                   let chapterPath = itemObj["chapter_path"] as? String,
                   let images = itemObj["chapter_image"] as? [[String: Any]] {

                    var pages: [MangaPage] = []
                    for (idx, imgObj) in images.enumerated() {
                        if let file = imgObj["image_file"] as? String {
                            pages.append(
                                MangaPage(
                                    index: idx,
                                    url: "\(domainCdn)/\(chapterPath)/\(file)",
                                    headers: currentAddon?.headers
                                )
                            )
                        }
                    }
                    if !pages.isEmpty { return pages }
                }
            }
        } catch {
            // Lỗi mạng/parse: trả về rỗng để Reader báo lỗi và cho phép thử lại
        }

        return []
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

    // MARK: - Helpers

    /// Tạo request chuẩn cho một nguồn: User-Agent di động + headers riêng của nguồn (nếu có).
    private func makeRequest(url: URL, addon: MangaAddon?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        addon?.headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    /// Ghép mẫu endpoint với baseUrl và thay các biến {query}, {id}, {page}.
    /// Đường dẫn bắt đầu bằng "/" được ghép sau baseUrl; URL đầy đủ giữ nguyên.
    private func resolveEndpoint(_ template: String, addon: MangaAddon, values: [String: String]) -> String? {
        var resolved = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return nil }
        for (key, value) in values {
            resolved = resolved.replacingOccurrences(of: "{\(key)}", with: value)
        }
        if resolved.hasPrefix("/") {
            let base = addon.baseUrl.hasSuffix("/") ? String(addon.baseUrl.dropLast()) : addon.baseUrl
            return base + resolved
        }
        return resolved
    }

    /// Parse danh sách trang ảnh từ mảng JSON: chấp nhận chuỗi URL thuần
    /// hoặc object {"url": "...", "headers": {...}}. Trang không khai báo headers
    /// sẽ kế thừa headers của nguồn (phục vụ CDN chống hotlink).
    private func parsePageArray(_ raw: Any, fallbackHeaders: [String: String]?) -> [MangaPage] {
        guard let array = raw as? [Any] else { return [] }
        var pages: [MangaPage] = []
        for (idx, element) in array.enumerated() {
            if let urlString = element as? String, !urlString.isEmpty {
                pages.append(MangaPage(index: idx, url: urlString, headers: fallbackHeaders))
            } else if let dict = element as? [String: Any],
                      let urlString = dict["url"] as? String, !urlString.isEmpty {
                let headers = (dict["headers"] as? [String: String]) ?? fallbackHeaders
                pages.append(MangaPage(index: idx, url: urlString, headers: headers))
            }
        }
        return pages
    }

    /// Tải và decode danh sách truyện. Chấp nhận các dạng JSON phổ biến:
    /// mảng [MangaItem] trực tiếp, hoặc wrapper {"data": [...]}, {"items": [...]}, {"results": [...]}.
    private func fetchMangaList(from url: URL, addon: MangaAddon) async -> Result<[MangaItem], MangaSourceError> {
        do {
            let (data, response) = try await session.data(for: makeRequest(url: url, addon: addon))
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse(sourceName: addon.name))
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure(.serverError(statusCode: httpResponse.statusCode, sourceName: addon.name))
            }

            if let items = try? JSONDecoder().decode([MangaItem].self, from: data) {
                return .success(items)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for wrapperKey in ["data", "items", "results"] {
                    if let rawArray = json[wrapperKey],
                       JSONSerialization.isValidJSONObject(rawArray),
                       let arrayData = try? JSONSerialization.data(withJSONObject: rawArray),
                       let items = try? JSONDecoder().decode([MangaItem].self, from: arrayData) {
                        return .success(items)
                    }
                }
            }

            return .failure(.invalidResponse(sourceName: addon.name))
        } catch {
            return .failure(mapNetworkError(error, sourceName: addon.name))
        }
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
}
