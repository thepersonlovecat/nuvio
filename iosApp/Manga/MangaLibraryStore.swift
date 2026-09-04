import Combine
import Foundation

public struct MangaFollowedSeries: Codable, Identifiable, Hashable {
    public let mangaID: String
    public var mangaTitle: String
    public var mangaCover: String
    public var mangaURL: String
    public var addonID: String
    public var knownChapterIDs: [String]
    public var unreadChapterIDs: [String]
    public var readChapterIDs: [String]?
    public var updatedAt: Date

    public var id: String { mangaID }
    public var unreadCount: Int { unreadChapterIDs.count }

    public init(manga: MangaItem, addonID: String) {
        mangaID = manga.id
        mangaTitle = manga.title
        mangaCover = manga.displayCover
        mangaURL = manga.url
        self.addonID = addonID
        knownChapterIDs = manga.chapters?.map(\.id) ?? []
        unreadChapterIDs = []
        readChapterIDs = []
        updatedAt = Date()
    }

    public var sourceManga: MangaItem {
        MangaItem(id: mangaID, title: mangaTitle, cover: mangaCover, url: mangaURL)
    }
}

/// Local library state. A followed series records the chapters known at the
/// moment it was followed; later refreshes can therefore identify new chapters.
public final class MangaLibraryStore: ObservableObject {
    public static let shared = MangaLibraryStore()

    private let storageKey = "nuvio_manga_library_v1"
    @Published public private(set) var followed: [MangaFollowedSeries] = []

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([MangaFollowedSeries].self, from: data) else {
            return
        }
        followed = stored
    }

    public func isFollowing(mangaID: String) -> Bool {
        followed.contains { $0.mangaID == mangaID }
    }

    public func follow(_ manga: MangaItem, addonID: String) {
        guard !isFollowing(mangaID: manga.id) else { return }
        followed.insert(MangaFollowedSeries(manga: manga, addonID: addonID), at: 0)
        persist()
    }

    public func unfollow(mangaID: String) {
        followed.removeAll { $0.mangaID == mangaID }
        persist()
    }

    public func refresh(_ manga: MangaItem) {
        guard let index = followed.firstIndex(where: { $0.mangaID == manga.id }) else { return }
        let incomingChapterIDs = manga.chapters?.map(\.id) ?? []
        let knownIDs = Set(followed[index].knownChapterIDs)
        let existingUnread = Set(followed[index].unreadChapterIDs)
        let newUnread = incomingChapterIDs.filter { !knownIDs.contains($0) && !existingUnread.contains($0) }

        followed[index].mangaTitle = manga.title
        followed[index].mangaCover = manga.displayCover
        followed[index].mangaURL = manga.url
        followed[index].knownChapterIDs = Array(knownIDs.union(incomingChapterIDs))
        followed[index].unreadChapterIDs.append(contentsOf: newUnread)
        followed[index].updatedAt = Date()
        persist()
    }

    public func markRead(mangaID: String, chapterID: String) {
        guard let index = followed.firstIndex(where: { $0.mangaID == mangaID }) else { return }
        if !(followed[index].readChapterIDs ?? []).contains(chapterID) {
            followed[index].readChapterIDs = (followed[index].readChapterIDs ?? []) + [chapterID]
        }
        followed[index].unreadChapterIDs.removeAll { $0 == chapterID }
        persist()
    }

    public func readChapterIDs(mangaID: String) -> Set<String> {
        Set(followed.first(where: { $0.mangaID == mangaID })?.readChapterIDs ?? [])
    }

    public func isRead(mangaID: String, chapterID: String) -> Bool {
        readChapterIDs(mangaID: mangaID).contains(chapterID)
    }

    public func markAllRead(mangaID: String, chapters: [MangaChapter]) {
        guard let index = followed.firstIndex(where: { $0.mangaID == mangaID }) else { return }
        followed[index].readChapterIDs = Array(
            Set(followed[index].readChapterIDs ?? []).union(chapters.map(\.id))
        )
        followed[index].unreadChapterIDs = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(followed) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
