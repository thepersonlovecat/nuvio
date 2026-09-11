import Foundation

// MARK: - IPTV Channel Model

public struct IPTVChannel: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var streamUrl: String
    public var logoUrl: String?
    public var groupTitle: String
    public var tvgId: String?
    public var tvgName: String?
    public var httpHeaders: [String: String]
    public var licenseType: String?   // e.g. "clearkey"
    public var licenseKey: String?    // e.g. "KID:KEY" or Hex Key for MPEG-DASH

    public init(
        id: String = UUID().uuidString,
        name: String,
        streamUrl: String,
        logoUrl: String? = nil,
        groupTitle: String = "Chung",
        tvgId: String? = nil,
        tvgName: String? = nil,
        httpHeaders: [String: String] = [:],
        licenseType: String? = nil,
        licenseKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.streamUrl = streamUrl
        self.logoUrl = logoUrl
        self.groupTitle = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Khác" : groupTitle
        self.tvgId = tvgId
        self.tvgName = tvgName
        self.httpHeaders = httpHeaders
        self.licenseType = licenseType
        self.licenseKey = licenseKey
    }

    /// Kiểm tra định dạng luồng phát
    public var isMPEG_DASH: Bool {
        streamUrl.lowercased().contains(".mpd")
    }

    public var isHLS: Bool {
        streamUrl.lowercased().contains(".m3u8")
    }

    public var isClearKey: Bool {
        (licenseType?.lowercased() == "clearkey") || (licenseKey != nil && !licenseKey!.isEmpty)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(streamUrl)
    }

    public static func == (lhs: IPTVChannel, rhs: IPTVChannel) -> Bool {
        lhs.id == rhs.id && lhs.streamUrl == rhs.streamUrl
    }
}

// MARK: - IPTV Playlist Model

public struct IPTVPlaylist: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var url: String
    public var channels: [IPTVChannel]
    public var lastUpdated: Date
    public var isBuiltIn: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        channels: [IPTVChannel] = [],
        lastUpdated: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.channels = channels
        self.lastUpdated = lastUpdated
        self.isBuiltIn = isBuiltIn
    }

    public var channelCount: Int {
        channels.count
    }

    /// Lấy danh sách các nhóm/danh mục có trong playlist
    public var categories: [String] {
        let uniqueGroups = Set(channels.map(\.groupTitle))
        return uniqueGroups.sorted()
    }
}

// MARK: - Filter Category

public struct IPTVCategoryItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let iconName: String
    public let count: Int

    public init(name: String, iconName: String = "tv", count: Int = 0) {
        self.id = name
        self.name = name
        self.iconName = iconName
        self.count = count
    }
}
