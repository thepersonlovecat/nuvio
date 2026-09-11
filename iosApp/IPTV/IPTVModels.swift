import Foundation

// MARK: - IPTV Playlist Type

public enum IPTVPlaylistType: String, Codable, CaseIterable {
    case m3u = "M3U / M3U8 Link"
    case localFile = "File M3U Máy"
    case xtream = "Xtream Codes"
    case stalker = "Stalker Portal"

    public var iconName: String {
        switch self {
        case .m3u: return "link"
        case .localFile: return "doc.fill"
        case .xtream: return "server.rack"
        case .stalker: return "antenna.radiowaves.left.and.right"
        }
    }
}

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
    public var type: IPTVPlaylistType
    public var url: String
    public var channels: [IPTVChannel]
    public var lastUpdated: Date

    // Xtream Codes Credentials
    public var xtreamServer: String?
    public var xtreamUsername: String?
    public var xtreamPassword: String?

    // Stalker Portal Credentials
    public var stalkerMac: String?

    // Local file stored path
    public var localFileName: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: IPTVPlaylistType = .m3u,
        url: String = "",
        channels: [IPTVChannel] = [],
        lastUpdated: Date = Date(),
        xtreamServer: String? = nil,
        xtreamUsername: String? = nil,
        xtreamPassword: String? = nil,
        stalkerMac: String? = nil,
        localFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.channels = channels
        self.lastUpdated = lastUpdated
        self.xtreamServer = xtreamServer
        self.xtreamUsername = xtreamUsername
        self.xtreamPassword = xtreamPassword
        self.stalkerMac = stalkerMac
        self.localFileName = localFileName
    }

    public var channelCount: Int {
        channels.count
    }

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
