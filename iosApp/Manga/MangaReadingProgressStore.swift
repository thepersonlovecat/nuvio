import Combine
import Foundation

public struct MangaReadingProgress: Codable, Identifiable, Hashable {
    public let mangaID: String
    public let mangaTitle: String
    public let mangaCover: String
    public let mangaURL: String
    public let chapter: MangaChapter
    public let pageIndex: Int
    public let pageCount: Int
    public let updatedAt: Date

    public var id: String { mangaID }
    public var completedPageCount: Int { min(pageIndex + 1, max(pageCount, 1)) }

    public init(
        manga: MangaItem,
        chapter: MangaChapter,
        pageIndex: Int,
        pageCount: Int,
        updatedAt: Date = Date()
    ) {
        mangaID = manga.id
        mangaTitle = manga.title
        mangaCover = manga.displayCover
        mangaURL = manga.url
        self.chapter = chapter
        self.pageIndex = max(0, pageIndex)
        self.pageCount = max(0, pageCount)
        self.updatedAt = updatedAt
    }

    public var resumeManga: MangaItem {
        MangaItem(
            id: mangaID,
            title: mangaTitle,
            cover: mangaCover,
            url: mangaURL,
            chapters: [chapter]
        )
    }
}

public final class MangaReadingProgressStore: ObservableObject {
    public static let shared = MangaReadingProgressStore()

    private let storageKey = "nuvio_manga_reading_progress_v1"
    @Published private var entries: [String: MangaReadingProgress] = [:]

    public var latest: MangaReadingProgress? {
        entries.values.max { $0.updatedAt < $1.updatedAt }
    }

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([String: MangaReadingProgress].self, from: data) else {
            return
        }
        entries = stored
    }

    public func save(manga: MangaItem, chapter: MangaChapter, pageIndex: Int, pageCount: Int) {
        entries[manga.id] = MangaReadingProgress(
            manga: manga,
            chapter: chapter,
            pageIndex: pageIndex,
            pageCount: pageCount
        )
        persist()
    }

    public func remove(mangaID: String) {
        entries.removeValue(forKey: mangaID)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
