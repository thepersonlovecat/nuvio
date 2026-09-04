import Foundation
import Combine

/// Quản trị viên quản lý các Manga Add-ons / Extensions
/// Hoàn toàn độc lập với hệ thống Addon phim và trang Home của Nuvio.
public final class MangaAddonManager: ObservableObject {
    public static let shared = MangaAddonManager()

    private let addonsKey = "nuvio_manga_addons_v1"
    private let activeKey = "nuvio_active_manga_addon_id_v1"

    @Published public var addons: [MangaAddon] = []
    @Published public var activeAddonId: String = ""

    /// Nguồn đang kích hoạt. Nil nếu người dùng chưa cài add-on nào -
    /// giao diện sẽ hiện hướng dẫn cài đặt thay vì dùng nguồn chèn cứng.
    public var activeAddon: MangaAddon? {
        addons.first(where: { $0.id == activeAddonId && $0.isEnabled })
            ?? addons.first(where: { $0.isEnabled })
    }

    private init() {
        loadAddons()
    }

    // MARK: - Nạp & Lưu Trữ Độc Lập
    private func loadAddons() {
        if let data = UserDefaults.standard.data(forKey: addonsKey),
           let saved = try? JSONDecoder().decode([MangaAddon].self, from: data) {
            // Migration: loại bỏ các nguồn built-in cũ từng được chèn cứng,
            // chỉ giữ lại add-on do người dùng tự cài.
            let userAddons = saved.filter { !$0.isBuiltIn }
            self.addons = userAddons
            if userAddons.count != saved.count {
                saveAddons()
            }
        }

        if let savedActive = UserDefaults.standard.string(forKey: activeKey),
           addons.contains(where: { $0.id == savedActive && $0.isEnabled }) {
            self.activeAddonId = savedActive
        } else {
            self.activeAddonId = addons.first(where: { $0.isEnabled })?.id ?? ""
        }
    }

    public func saveAddons() {
        if let data = try? JSONEncoder().encode(addons) {
            UserDefaults.standard.set(data, forKey: addonsKey)
        }
        UserDefaults.standard.set(activeAddonId, forKey: activeKey)
    }

    // MARK: - Hành Động Quản Lý Add-on
    public func selectAddon(id: String) {
        guard let target = addons.first(where: { $0.id == id && $0.isEnabled }) else { return }
        self.activeAddonId = target.id
        UserDefaults.standard.set(target.id, forKey: activeKey)
    }

    public func toggleAddon(id: String) {
        guard let idx = addons.firstIndex(where: { $0.id == id }) else { return }
        addons[idx].isEnabled.toggle()

        // Nếu nguồn đang kích hoạt bị tắt, tự chuyển sang nguồn bật tiếp theo
        if activeAddonId == id && !addons[idx].isEnabled {
            if let nextEnabled = addons.first(where: { $0.isEnabled }) {
                activeAddonId = nextEnabled.id
            }
        }
        saveAddons()
    }

    public func removeAddon(id: String) {
        guard let idx = addons.firstIndex(where: { $0.id == id }) else { return }
        addons.remove(at: idx)
        if activeAddonId == id {
            activeAddonId = addons.first(where: { $0.isEnabled })?.id ?? ""
        }
        saveAddons()
    }

    // MARK: - Cài Đặt Add-on từ URL (Manifest hoặc Provider-Z JSON)
    public func installAddon(from urlString: String) async throws -> MangaAddon {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw AddonError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AddonError.serverError
        }

        // 1. Thử parse dạng chuẩn MangaAddonManifest
        if let manifest = try? JSONDecoder().decode(MangaAddonManifest.self, from: data) {
            let newAddon = manifest.toAddon(manifestUrl: trimmed)
            await appendAndSave(newAddon)
            return newAddon
        }

        // 2. Thử parse dạng cấu hình JSON Provider-Z
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let id = json["id"] as? String ?? url.deletingPathExtension().lastPathComponent
            let name = json["name"] as? String ?? json["title"] as? String ?? id
            let version = json["version"] as? String ?? "1.0.0"
            let desc = json["description"] as? String ?? "Custom Provider-Z Extension"
            let baseUrl = json["baseUrl"] as? String ?? json["url"] as? String ?? trimmed
            let icon = json["icon"] as? String ?? json["iconUrl"] as? String
            let headers = json["headers"] as? [String: String]

            var endpoints: MangaAddonEndpoints?
            if let rawEndpoints = json["endpoints"] as? [String: String] {
                endpoints = MangaAddonEndpoints(
                    home: rawEndpoints["home"],
                    search: rawEndpoints["search"],
                    detail: rawEndpoints["detail"],
                    chapter: rawEndpoints["chapter"]
                )
            }

            let newAddon = MangaAddon(
                id: id,
                name: name,
                version: version,
                description: desc,
                baseUrl: baseUrl,
                iconUrl: icon,
                manifestUrl: trimmed,
                type: .providerZJson,
                isEnabled: true,
                isBuiltIn: false,
                endpoints: endpoints,
                headers: headers
            )
            await appendAndSave(newAddon)
            return newAddon
        }

        throw AddonError.invalidFormat
    }

    @MainActor
    private func appendAndSave(_ addon: MangaAddon) {
        if let idx = addons.firstIndex(where: { $0.id == addon.id }) {
            addons[idx] = addon
        } else {
            addons.append(addon)
        }
        activeAddonId = addon.id
        saveAddons()
    }
}

// MARK: - Addon Errors
public enum AddonError: LocalizedError {
    case invalidUrl
    case serverError
    case invalidFormat

    public var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Đường dẫn URL không hợp lệ. Vui lòng nhập link bắt đầu bằng http:// hoặc https://"
        case .serverError:
            return "Không thể tải cấu hình từ máy chủ máy cung cấp (Mã phản hồi lỗi)."
        case .invalidFormat:
            return "Định dạng Add-on không tương thích. Vui lòng kiểm tra file manifest JSON hoặc Provider-Z."
        }
    }
}
