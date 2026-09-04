import Foundation

// MARK: - Manga Item Model
public struct MangaItem: Identifiable, Codable, Hashable {
    public let id: String
    public let title: String
    public let cover: String
    public let posterUrl: String?
    public let url: String
    public let description: String?
    public let status: String?
    public let genres: [String]?
    public let authors: [String]?
    public let chapters: [MangaChapter]?

    public init(
        id: String,
        title: String,
        cover: String,
        posterUrl: String? = nil,
        url: String,
        description: String? = nil,
        status: String? = nil,
        genres: [String]? = nil,
        authors: [String]? = nil,
        chapters: [MangaChapter]? = nil
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.posterUrl = posterUrl ?? cover
        self.url = url
        self.description = description
        self.status = status
        self.genres = genres
        self.authors = authors
        self.chapters = chapters
    }

    public var displayCover: String {
        if !cover.isEmpty { return cover }
        return posterUrl ?? ""
    }
}

// MARK: - Manga Chapter Model
public struct MangaChapter: Identifiable, Codable, Hashable {
    public let id: String
    public let title: String
    public let chapterName: String?
    public let url: String
    public let date: String?

    public init(
        id: String,
        title: String,
        chapterName: String? = nil,
        url: String,
        date: String? = nil
    ) {
        self.id = id
        self.title = title
        self.chapterName = chapterName
        self.url = url
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case chapterName = "chapter_name"
        case url
        case date
    }
}

/// Keeps the manga details alive while the detail sheet is dismissed before
/// presenting the reader as a full-screen cover.
public struct MangaReadingSession: Identifiable {
    public let manga: MangaItem
    public let chapter: MangaChapter
    public let initialPageIndex: Int

    public var id: String { "\(manga.id)::\(chapter.id)" }

    public init(manga: MangaItem, chapter: MangaChapter, initialPageIndex: Int = 0) {
        self.manga = manga
        self.chapter = chapter
        self.initialPageIndex = max(0, initialPageIndex)
    }
}

// MARK: - Manga Page Model
public struct MangaPage: Identifiable, Codable, Hashable {
    public var id: String { "\(index)_\(url)" }
    public let index: Int
    public let url: String
    public let headers: [String: String]?

    public init(index: Int, url: String, headers: [String: String]? = nil) {
        self.index = index
        self.url = url
        self.headers = headers
    }
}

// MARK: - Reading Mode
public enum ReadingMode: String, CaseIterable, Identifiable {
    case webtoon = "Cuộn dọc (Webtoon)"
    case paged = "Lật trang (Manga)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .webtoon: return "scroll.fill"
        case .paged: return "book.pages.fill"
        }
    }
}

// MARK: - Manga Add-on Type
public enum MangaAddonType: String, Codable, CaseIterable {
    case builtInRest = "built_in"
    case providerZJson = "provider_z_json"
    case customRest = "custom_rest"

    public var displayName: String {
        switch self {
        case .builtInRest: return "Nguồn tích hợp"
        case .providerZJson: return "Provider-Z"
        case .customRest: return "REST API"
        }
    }
}

// MARK: - Manga Add-on Definition
public struct MangaAddon: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var version: String
    public var description: String
    public var baseUrl: String
    public var iconUrl: String?
    public var manifestUrl: String?
    public var type: MangaAddonType
    public var isEnabled: Bool
    public var isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        version: String = "1.0.0",
        description: String = "",
        baseUrl: String,
        iconUrl: String? = nil,
        manifestUrl: String? = nil,
        type: MangaAddonType = .builtInRest,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.baseUrl = baseUrl
        self.iconUrl = iconUrl
        self.manifestUrl = manifestUrl
        self.type = type
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Add-on Manifest DTO (For remote installation via JSON URL)
public struct MangaAddonManifest: Codable {
    public let id: String
    public let name: String
    public let version: String?
    public let description: String?
    public let baseUrl: String?
    public let icon: String?
    public let type: String?

    public func toAddon(manifestUrl: String) -> MangaAddon {
        MangaAddon(
            id: id,
            name: name,
            version: version ?? "1.0.0",
            description: description ?? "",
            baseUrl: baseUrl ?? manifestUrl,
            iconUrl: icon,
            manifestUrl: manifestUrl,
            type: .providerZJson,
            isEnabled: true,
            isBuiltIn: false
        )
    }
}
