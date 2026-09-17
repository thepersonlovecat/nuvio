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
    public var manifestType: String?  // e.g. "mpd" or "hls"

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
        licenseKey: String? = nil,
        manifestType: String? = nil
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
        self.manifestType = manifestType
    }

    public var isMPEG_DASH: Bool {
        streamUrl.lowercased().contains(".mpd") || (manifestType?.lowercased() == "mpd")
    }

    public var isHLS: Bool {
        streamUrl.lowercased().contains(".m3u8") || (manifestType?.lowercased() == "hls")
    }

    public var isClearKey: Bool {
        (licenseType?.lowercased() == "clearkey") || (licenseKey != nil && !licenseKey!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public var clearKeyOnly: String? {
        Self.extractKeyHex(from: licenseKey)
    }

    public var clearKeyKid: String? {
        Self.extractKidHex(from: licenseKey)
    }

    // MARK: - ClearKey Hex Extraction Helpers

    public static func extractKeyHex(from rawInput: String?) -> String? {
        guard let rawInput else { return nil }
        var cleaned = rawInput.replacingOccurrences(of: "--key", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if cleaned.isEmpty { return nil }

        // 1. JSON JWK or Kodi dictionary format
        if cleaned.hasPrefix("{") {
            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // JWK format: {"keys":[{"kty":"oct","k":"...","kid":"..."}]}
                if let keys = json["keys"] as? [[String: Any]],
                   let firstKey = keys.first,
                   let kB64 = firstKey["k"] as? String,
                   let hex = decodeBase64URLToHex(kB64) {
                    return cleanHex(hex)
                }
                // Kodi JSON dictionary format: {"<KID>": "<KEY>"}
                for (_, val) in json {
                    if let keyStr = val as? String, !keyStr.isEmpty {
                        return cleanHex(keyStr)
                    }
                }
            }
            if let regex = try? NSRegularExpression(pattern: "\"k\"\\s*:\\s*\"([^\"]+)\""),
               let match = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: cleaned.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: cleaned),
               let hex = decodeBase64URLToHex(String(cleaned[range])) {
                return cleanHex(hex)
            }
        }

        // 2. KID:KEY format -> take KEY (second/last component)
        if cleaned.contains(":") {
            let parts = cleaned.components(separatedBy: ":")
            if parts.count >= 2 {
                let candidate = parts[parts.count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return cleanHex(candidate) }
            }
        }

        return cleanHex(cleaned)
    }

    public static func extractKidHex(from rawInput: String?) -> String? {
        guard let rawInput else { return nil }
        var cleaned = rawInput.replacingOccurrences(of: "--key", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if cleaned.isEmpty { return nil }

        if cleaned.hasPrefix("{") {
            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // JWK format
                if let keys = json["keys"] as? [[String: Any]],
                   let firstKey = keys.first,
                   let kidB64 = firstKey["kid"] as? String,
                   let hex = decodeBase64URLToHex(kidB64) {
                    return cleanHex(hex)
                }
                // Kodi JSON dictionary format: {"<KID>": "<KEY>"}
                if let firstKid = json.keys.first, !firstKid.isEmpty {
                    return cleanHex(firstKid)
                }
            }
        }

        if cleaned.contains(":") {
            let parts = cleaned.components(separatedBy: ":")
            if parts.count >= 2 {
                let candidate = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return cleanHex(candidate) }
            }
        }

        return nil
    }

    public static func cleanHex(_ input: String) -> String {
        return input
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func decodeBase64URLToHex(_ b64url: String) -> String? {
        var base64 = b64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padLength = (4 - (base64.count % 4)) % 4
        base64.append(String(repeating: "=", count: padLength))

        guard let data = Data(base64Encoded: base64) else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
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
