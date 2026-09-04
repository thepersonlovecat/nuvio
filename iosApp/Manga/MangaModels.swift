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
