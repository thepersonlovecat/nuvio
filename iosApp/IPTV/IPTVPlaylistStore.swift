import Foundation
import Combine
import SwiftUI

@MainActor
public final class IPTVPlaylistStore: ObservableObject {

    public static let shared = IPTVPlaylistStore()

    private let storageFileName = "nuvio_iptv_playlists_v2.json"
    private let favoritesKey = "nuvio_iptv_favorites_v1"
    private let recentsKey = "nuvio_iptv_recents_v1"
    private let activePlaylistIdKey = "nuvio_iptv_active_id_v2"

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

        // Xóa sạch kênh mẫu cũ nếu có
        playlists.removeAll { $0.id == "builtin_vietnam_essential" }

        if activePlaylistId == nil || !playlists.contains(where: { $0.id == activePlaylistId }) {
            activePlaylistId = playlists.first?.id
        }
    }

    public var activePlaylist: IPTVPlaylist? {
        playlists.first(where: { $0.id == activePlaylistId }) ?? playlists.first
    }

    public var currentChannels: [IPTVChannel] {
        activePlaylist?.channels ?? []
    }

    // MARK: - Playlist Operations

    public func selectPlaylist(id: String) {
        activePlaylistId = id
        UserDefaults.standard.set(id, forKey: activePlaylistIdKey)
    }

    // 1. Thêm M3U Link
    public func addM3UPlaylist(name: String, url: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let channels = try await IPTVParser.shared.fetchAndParse(from: url)
            guard !channels.isEmpty else {
                errorMessage = "Không tìm thấy kênh nào trong danh sách phát M3U này."
                isLoading = false
                return false
            }

            let playlist = IPTVPlaylist(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Danh sách M3U" : name,
                type: .m3u,
                url: url,
                channels: channels,
                lastUpdated: Date()
            )

            playlists.append(playlist)
            selectPlaylist(id: playlist.id)
            persistPlaylists()
            isLoading = false
            return true
        } catch {
            errorMessage = "Lỗi tải M3U: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    // 2. Thêm File M3U Local từ máy
    public func addLocalFilePlaylist(name: String, sourceURL: URL) async -> Bool {
        isLoading = true
        errorMessage = nil

        guard sourceURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Không có quyền truy cập file đã chọn."
            isLoading = false
            return false
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: sourceURL)
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                errorMessage = "Không thể đọc nội dung file văn bản."
                isLoading = false
                return false
            }

            let channels = IPTVParser.shared.parse(m3uContent: content)
            guard !channels.isEmpty else {
                errorMessage = "File không chứa bất kỳ kênh hợp lệ nào."
                isLoading = false
                return false
            }

            // Lưu bản sao vào thư mục Documents của App
            let localFileName = "\(UUID().uuidString)_\(sourceURL.lastPathComponent)"
            let destURL = documentsDirectory.appendingPathComponent(localFileName)
            try data.write(to: destURL, options: .atomic)

            let playlist = IPTVPlaylist(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : name,
                type: .localFile,
                url: destURL.path,
                channels: channels,
                lastUpdated: Date(),
                localFileName: localFileName
            )

            playlists.append(playlist)
            selectPlaylist(id: playlist.id)
            persistPlaylists()
            isLoading = false
            return true
        } catch {
            errorMessage = "Lỗi nạp file: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    // 3. Thêm Xtream Codes
    public func addXtreamPlaylist(name: String, server: String, user: String, pass: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let channels = try await IPTVParser.shared.fetchXtreamChannels(server: server, user: user, pass: pass)
            guard !channels.isEmpty else {
                errorMessage = "Máy chủ Xtream không trả về kênh phát nào."
                isLoading = false
                return false
            }

            let playlist = IPTVPlaylist(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Xtream Server" : name,
                type: .xtream,
                url: server,
                channels: channels,
                lastUpdated: Date(),
                xtreamServer: server,
                xtreamUsername: user,
                xtreamPassword: pass
            )

            playlists.append(playlist)
            selectPlaylist(id: playlist.id)
            persistPlaylists()
            isLoading = false
            return true
        } catch {
            errorMessage = "Lỗi Xtream Codes: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    // 4. Thêm Stalker Portal
    public func addStalkerPlaylist(name: String, portalUrl: String, mac: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let channels = try await IPTVParser.shared.fetchStalkerChannels(portalUrl: portalUrl, mac: mac)
            guard !channels.isEmpty else {
                errorMessage = "Stalker Portal không có kênh nào khả dụng."
                isLoading = false
                return false
            }

            let playlist = IPTVPlaylist(
                id: UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Stalker Portal" : name,
                type: .stalker,
                url: portalUrl,
                channels: channels,
                lastUpdated: Date(),
                stalkerMac: mac
            )

            playlists.append(playlist)
            selectPlaylist(id: playlist.id)
            persistPlaylists()
            isLoading = false
            return true
        } catch {
            errorMessage = "Lỗi Stalker: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    // 5. Cập nhật / Sửa Playlist (Edit)
    public func updatePlaylist(id: String, newName: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = newName
        persistPlaylists()
    }

    // 6. Xóa Playlist (Remove)
    public func deletePlaylist(id: String) {
        if let pl = playlists.first(where: { $0.id == id }), let localFile = pl.localFileName {
            let fileURL = documentsDirectory.appendingPathComponent(localFile)
            try? FileManager.default.removeItem(at: fileURL)
        }

        playlists.removeAll(where: { $0.id == id })
        if activePlaylistId == id {
            activePlaylistId = playlists.first?.id
            UserDefaults.standard.set(activePlaylistId, forKey: activePlaylistIdKey)
        }
        persistPlaylists()
    }

    // 7. Làm mới Playlist (Refresh)
    public func refreshPlaylist(id: String) async {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let playlist = playlists[index]

        isLoading = true
        errorMessage = nil

        do {
            var freshChannels: [IPTVChannel] = []

            switch playlist.type {
            case .m3u:
                freshChannels = try await IPTVParser.shared.fetchAndParse(from: playlist.url)
            case .xtream:
                if let s = playlist.xtreamServer, let u = playlist.xtreamUsername, let p = playlist.xtreamPassword {
                    freshChannels = try await IPTVParser.shared.fetchXtreamChannels(server: s, user: u, pass: p)
                }
            case .stalker:
                if let m = playlist.stalkerMac {
                    freshChannels = try await IPTVParser.shared.fetchStalkerChannels(portalUrl: playlist.url, mac: m)
                }
            case .localFile:
                if let localFile = playlist.localFileName {
                    let fileURL = documentsDirectory.appendingPathComponent(localFile)
                    if let data = try? Data(contentsOf: fileURL),
                       let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                        freshChannels = IPTVParser.shared.parse(m3uContent: content)
                    }
                }
            }

            if !freshChannels.isEmpty {
                playlists[index].channels = freshChannels
                playlists[index].lastUpdated = Date()
                persistPlaylists()
            }
        } catch {
            errorMessage = "Không thể làm mới: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Favorites & Recents

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

    public func recordRecent(channel: IPTVChannel) {
        var updated = recentChannels.filter { $0.streamUrl != channel.streamUrl }
        updated.insert(channel, at: 0)
        if updated.count > 30 {
            updated = Array(updated.prefix(30))
        }
        recentChannels = updated
        persistRecents()
    }

    // MARK: - Persistence

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var storageFileURL: URL {
        documentsDirectory.appendingPathComponent(storageFileName)
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
}
