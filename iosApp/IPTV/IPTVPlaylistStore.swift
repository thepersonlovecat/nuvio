import Foundation
import Combine
import SwiftUI

@MainActor
public final class IPTVPlaylistStore: ObservableObject {

    public static let shared = IPTVPlaylistStore()

    private let storageFileName = "nuvio_iptv_playlists_v1.json"
    private let favoritesKey = "nuvio_iptv_favorites_v1"
    private let recentsKey = "nuvio_iptv_recents_v1"
    private let activePlaylistIdKey = "nuvio_iptv_active_id_v1"

    @Published public var playlists: [IPTVPlaylist] = []
    @Published public var activePlaylistId: String? = nil
    @Published public var favoriteIDs: Set<String> = []
    @Published public var recentChannels: [IPTVChannel] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private init() {
        loadFavorites()
        loadRecents()
        loadPlaylists()

        // Nếu chưa có playlist nào, tạo playlist mẫu mặc định
        if playlists.isEmpty {
            createDefaultSamplePlaylist()
        }

        if activePlaylistId == nil || !playlists.contains(where: { $0.id == activePlaylistId }) {
            activePlaylistId = playlists.first?.id
        }
    }

    /// Playlist đang được kích hoạt hiển thị
    public var activePlaylist: IPTVPlaylist? {
        playlists.first(where: { $0.id == activePlaylistId }) ?? playlists.first
    }

    /// Tất cả kênh của playlist hiện tại
    public var currentChannels: [IPTVChannel] {
        activePlaylist?.channels ?? []
    }

    // MARK: - Playlist Operations

    public func selectPlaylist(id: String) {
        activePlaylistId = id
        UserDefaults.standard.set(id, forKey: activePlaylistIdKey)
    }

    public func addPlaylist(name: String, url: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let channels = try await IPTVParser.shared.fetchAndParse(from: url)
            guard !channels.isEmpty else {
                errorMessage = "Không tìm thấy kênh nào trong danh sách phát này."
                isLoading = false
                return false
            }

            let newPlaylist = IPTVPlaylist(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Danh sách mới" : name,
                url: url,
                channels: channels,
                lastUpdated: Date(),
                isBuiltIn: false
            )

            playlists.append(newPlaylist)
            activePlaylistId = newPlaylist.id
            UserDefaults.standard.set(newPlaylist.id, forKey: activePlaylistIdKey)
            persistPlaylists()
            isLoading = false
            return true
        } catch {
            errorMessage = "Lỗi tải playlist: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    public func refreshPlaylist(id: String) async {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let playlist = playlists[index]
        guard !playlist.url.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let channels = try await IPTVParser.shared.fetchAndParse(from: playlist.url)
            if !channels.isEmpty {
                playlists[index].channels = channels
                playlists[index].lastUpdated = Date()
                persistPlaylists()
            }
        } catch {
            errorMessage = "Không thể làm mới: \(error.localizedDescription)"
        }

        isLoading = false
    }

    public func deletePlaylist(id: String) {
        playlists.removeAll(where: { $0.id == id })
        if activePlaylistId == id {
            activePlaylistId = playlists.first?.id
            UserDefaults.standard.set(activePlaylistId, forKey: activePlaylistIdKey)
        }
        persistPlaylists()
    }

    // MARK: - Favorites

    public func isFavorite(channel: IPTVChannel) -> Bool {
        favoriteIDs.contains(channel.streamUrl) || favoriteIDs.contains(channel.id)
    }

    public func toggleFavorite(channel: IPTVChannel) {
        let key = channel.streamUrl
        if favoriteIDs.contains(key) {
            favoriteIDs.remove(key)
        } else {
            favoriteIDs.insert(key)
        }
        persistFavorites()
    }

    public var favoriteChannels: [IPTVChannel] {
        currentChannels.filter { isFavorite(channel: $0) }
    }

    // MARK: - Recents

    public func recordRecent(channel: IPTVChannel) {
        var updated = recentChannels.filter { $0.streamUrl != channel.streamUrl }
        updated.insert(channel, at: 0)
        if updated.count > 25 {
            updated = Array(updated.prefix(25))
        }
        recentChannels = updated
        persistRecents()
    }

    // MARK: - Persistence

    private var storageFileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(storageFileName)
    }

    private func persistPlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: storageFileURL, options: [.atomic])
        } catch {
            print("[IPTV] Failed to save playlists: \(error)")
        }
    }

    private func loadPlaylists() {
        guard FileManager.default.fileExists(atPath: storageFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageFileURL)
            playlists = try JSONDecoder().decode([IPTVPlaylist].self, from: data)
            activePlaylistId = UserDefaults.standard.string(forKey: activePlaylistIdKey)
        } catch {
            print("[IPTV] Failed to load playlists: \(error)")
        }
    }

    private func persistFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }

    private func loadFavorites() {
        let array = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        favoriteIDs = Set(array)
    }

    private func persistRecents() {
        if let data = try? JSONEncoder().encode(recentChannels) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    private func loadRecents() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let channels = try? JSONDecoder().decode([IPTVChannel].self, from: data) {
            recentChannels = channels
        }
    }

    // MARK: - Default Sample Playlist
    private func createDefaultSamplePlaylist() {
        let sampleM3U = """
        #EXTM3U
        #EXTINF:-1 tvg-id="VTV1.vn" tvg-name="VTV1" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/VTV1_logo_2013_final.svg/240px-VTV1_logo_2013_final.svg.png" group-title="Thời Sự",VTV1 HD
        https://vtv1.vtvgo.vn/vtv1_hd.m3u8
        #EXTINF:-1 tvg-id="VTV2.vn" tvg-name="VTV2" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/VTV2_logo_2013_final.svg/240px-VTV2_logo_2013_final.svg.png" group-title="Khoa Giáo",VTV2 HD
        https://vtv2.vtvgo.vn/vtv2_hd.m3u8
        #EXTINF:-1 tvg-id="VTV3.vn" tvg-name="VTV3" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/7/77/VTV3_logo_2013_final.svg/240px-VTV3_logo_2013_final.svg.png" group-title="Giải Trí",VTV3 HD
        https://vtv3.vtvgo.vn/vtv3_hd.m3u8
        #EXTINF:-1 tvg-id="VTV4.vn" tvg-name="VTV4" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/b/b3/VTV4_logo_2013_final.svg/240px-VTV4_logo_2013_final.svg.png" group-title="Đối Ngoại",VTV4 HD
        https://vtv4.vtvgo.vn/vtv4_hd.m3u8
        #EXTINF:-1 tvg-id="VTV5.vn" tvg-name="VTV5" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/VTV5_logo_2013_final.svg/240px-VTV5_logo_2013_final.svg.png" group-title="Dân Tộc",VTV5 HD
        https://vtv5.vtvgo.vn/vtv5_hd.m3u8
        #EXTINF:-1 tvg-id="VTV7.vn" tvg-name="VTV7" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/VTV7_logo_final.svg/240px-VTV7_logo_final.svg.png" group-title="Giáo Dục",VTV7 HD
        https://vtv7.vtvgo.vn/vtv7_hd.m3u8
        #EXTINF:-1 tvg-id="VTV9.vn" tvg-name="VTV9" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/9/90/VTV9_logo_2013_final.svg/240px-VTV9_logo_2013_final.svg.png" group-title="Thời Sự",VTV9 HD
        https://vtv9.vtvgo.vn/vtv9_hd.m3u8
        #EXTINF:-1 tvg-id="QuocHoiTV.vn" tvg-name="Quoc Hoi TV" tvg-logo="https://quochoitv.vn/Images/logo.png" group-title="Thời Sự",Truyền Hình Quốc Hội
        https://quochoitv.vn/live/live.m3u8
        #EXTINF:-1 tvg-id="VOVTV.vn" tvg-name="VOV TV" tvg-logo="https://upload.wikimedia.org/wikipedia/vi/thumb/9/9f/VOV_TV_logo.svg/240px-VOV_TV_logo.svg.png" group-title="Thời Sự",VOV TV HD
        https://vovtv.vov.vn/live/live.m3u8
        """

        let defaultChannels = IPTVParser.shared.parse(m3uContent: sampleM3U)
        let samplePlaylist = IPTVPlaylist(
            id: "builtin_vietnam_essential",
            name: "Kênh Truyền Hình Mẫu",
            url: "https://iptv-org.github.io/iptv/countries/vn.m3u",
            channels: defaultChannels,
            lastUpdated: Date(),
            isBuiltIn: true
        )

        playlists = [samplePlaylist]
        activePlaylistId = samplePlaylist.id
        persistPlaylists()
    }
}
