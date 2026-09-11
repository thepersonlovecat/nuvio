import Foundation

public final class IPTVParser {

    public static let shared = IPTVParser()

    private init() {}

    // MARK: - M3U / M3U8 Parsing

    public func parse(m3uContent: String) -> [IPTVChannel] {
        var channels: [IPTVChannel] = []
        let lines = m3uContent.components(separatedBy: .newlines)

        var currentName = ""
        var currentLogo: String? = nil
        var currentGroup = "Chung"
        var currentTvgId: String? = nil
        var currentTvgName: String? = nil
        var currentHeaders: [String: String] = [:]
        var currentLicenseType: String? = nil
        var currentLicenseKey: String? = nil

        var hasPendingMetadata = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF:") {
                currentHeaders = [:]
                currentLicenseType = nil
                currentLicenseKey = nil

                parseExtInf(
                    line: line,
                    name: &currentName,
                    logo: &currentLogo,
                    group: &currentGroup,
                    tvgId: &currentTvgId,
                    tvgName: &currentTvgName
                )
                hasPendingMetadata = true
            } else if line.hasPrefix("#EXTVLCOPT:") {
                let opt = String(line.dropFirst("#EXTVLCOPT:".count))
                if let eqIndex = opt.firstIndex(of: "=") {
                    let key = String(opt[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                    let val = String(opt[opt.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

                    if key.lowercased() == "http-user-agent" {
                        currentHeaders["User-Agent"] = val
                    } else if key.lowercased() == "http-referrer" || key.lowercased() == "http-referer" {
                        currentHeaders["Referer"] = val
                    }
                }
            } else if line.hasPrefix("#KODIPROP:") {
                let prop = String(line.dropFirst("#KODIPROP:".count))
                if let eqIndex = prop.firstIndex(of: "=") {
                    let key = String(prop[..<eqIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                    let val = String(prop[prop.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

                    if key.contains("license_type") {
                        currentLicenseType = val
                    } else if key.contains("license_key") {
                        currentLicenseKey = val
                    }
                }
            } else if !line.hasPrefix("#") {
                var streamUrl = line

                if let pipeIndex = streamUrl.firstIndex(of: "|") {
                    let headerPart = String(streamUrl[streamUrl.index(after: pipeIndex)...])
                    streamUrl = String(streamUrl[..<pipeIndex])

                    let pairs = headerPart.components(separatedBy: "&")
                    for pair in pairs {
                        let parts = pair.components(separatedBy: "=")
                        if parts.count >= 2 {
                            let hKey = parts[0].trimmingCharacters(in: .whitespaces)
                            let hVal = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                            currentHeaders[hKey] = hVal
                        }
                    }
                }

                if hasPendingMetadata {
                    let channel = IPTVChannel(
                        id: UUID().uuidString,
                        name: currentName.isEmpty ? "Kênh không tên" : currentName,
                        streamUrl: streamUrl,
                        logoUrl: currentLogo,
                        groupTitle: currentGroup,
                        tvgId: currentTvgId,
                        tvgName: currentTvgName,
                        httpHeaders: currentHeaders,
                        licenseType: currentLicenseType,
                        licenseKey: currentLicenseKey
                    )
                    channels.append(channel)
                    hasPendingMetadata = false
                }
            }
        }

        return channels
    }

    private func parseExtInf(
        line: String,
        name: inout String,
        logo: inout String?,
        group: inout String,
        tvgId: inout String?,
        tvgName: inout String?
    ) {
        if let commaIndex = line.lastIndex(of: ",") {
            name = String(line[line.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
        } else {
            name = "Kênh"
        }

        tvgId = extractAttribute(key: "tvg-id", from: line)
        tvgName = extractAttribute(key: "tvg-name", from: line)
        logo = extractAttribute(key: "tvg-logo", from: line)
        if let grp = extractAttribute(key: "group-title", from: line), !grp.isEmpty {
            group = grp
        } else {
            group = "Chung"
        }
    }

    private func extractAttribute(key: String, from text: String) -> String? {
        let pattern = "\(key)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        guard let match = results.first, match.numberOfRanges > 1 else {
            return nil
        }
        return nsString.substring(with: match.range(at: 1))
    }

    public func fetchAndParse(from urlString: String) async throws -> [IPTVChannel] {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpRes = response as? HTTPURLResponse, httpRes.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }

        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw URLError(.cannotDecodeContentData)
        }

        return parse(m3uContent: content)
    }

    // MARK: - Xtream Codes API

    public func fetchXtreamChannels(server: String, user: String, pass: String) async throws -> [IPTVChannel] {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }

        guard let authUrl = URL(string: "\(base)/player_api.php?username=\(user)&password=\(pass)") else {
            throw URLError(.badURL)
        }

        // 1. Xác thực tài khoản
        var authRequest = URLRequest(url: authUrl)
        authRequest.timeoutInterval = 20
        authRequest.setValue("IPTVSmartersPlayer", forHTTPHeaderField: "User-Agent")

        let (authData, authResponse) = try await URLSession.shared.data(for: authRequest)
        if let httpRes = authResponse as? HTTPURLResponse, httpRes.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }

        guard let authJson = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let userInfo = authJson["user_info"] as? [String: Any],
              let authStatus = userInfo["auth"] as? Int, authStatus == 1 else {
            throw NSError(domain: "XtreamCodes", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sai thông tin đăng nhập hoặc tài khoản hết hạn"])
        }

        // 2. Lấy danh mục kênh
        var categoryMap: [String: String] = [:]
        if let catUrl = URL(string: "\(base)/player_api.php?username=\(user)&password=\(pass)&action=get_live_categories") {
            var catRequest = URLRequest(url: catUrl)
            catRequest.timeoutInterval = 20
            catRequest.setValue("IPTVSmartersPlayer", forHTTPHeaderField: "User-Agent")
            if let (catData, _) = try? await URLSession.shared.data(for: catRequest),
               let catList = try? JSONSerialization.jsonObject(with: catData) as? [[String: Any]] {
                for item in catList {
                    if let cid = item["category_id"] as? String ?? (item["category_id"] as? Int).map(String.init),
                       let cname = item["category_name"] as? String {
                        categoryMap[cid] = cname
                    }
                }
            }
        }

        // 3. Lấy danh sách luồng phát trực tiếp
        guard let streamsUrl = URL(string: "\(base)/player_api.php?username=\(user)&password=\(pass)&action=get_live_streams") else {
            throw URLError(.badURL)
        }

        var streamsRequest = URLRequest(url: streamsUrl)
        streamsRequest.timeoutInterval = 30
        streamsRequest.setValue("IPTVSmartersPlayer", forHTTPHeaderField: "User-Agent")

        let (streamsData, _) = try await URLSession.shared.data(for: streamsRequest)
        guard let streamList = try? JSONSerialization.jsonObject(with: streamsData) as? [[String: Any]] else {
            throw NSError(domain: "XtreamCodes", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc danh sách kênh từ máy chủ Xtream"])
        }

        var channels: [IPTVChannel] = []
        channels.reserveCapacity(streamList.count)

        for item in streamList {
            guard let name = item["name"] as? String else { continue }
            let streamId = item["stream_id"] as? Int ?? Int((item["stream_id"] as? String) ?? "") ?? 0
            guard streamId > 0 else { continue }

            let categoryId = item["category_id"] as? String ?? (item["category_id"] as? Int).map(String.init) ?? ""
            let groupName = categoryMap[categoryId] ?? "Khác"
            let logoUrl = item["stream_icon"] as? String
            let tvgId = item["epg_channel_id"] as? String

            // URL luồng phát chuẩn Xtream: http://server:port/live/user/pass/stream_id.m3u8
            let streamUrl = "\(base)/live/\(user)/\(pass)/\(streamId).m3u8"

            let channel = IPTVChannel(
                id: "\(base)_\(streamId)",
                name: name,
                streamUrl: streamUrl,
                logoUrl: logoUrl,
                groupTitle: groupName,
                tvgId: tvgId,
                tvgName: name,
                httpHeaders: ["User-Agent": "IPTVSmartersPlayer"]
            )
            channels.append(channel)
        }

        return channels
    }

    // MARK: - Stalker Portal API (MAG)

    public func fetchStalkerChannels(portalUrl: String, mac: String) async throws -> [IPTVChannel] {
        var base = portalUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") {
            base.removeLast()
        }
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }

        // Một số server Stalker hỗ trợ xuất M3U trực tiếp qua endpoint playlist
        let directM3UUrls = [
            "\(base)/playlist.m3u?mac=\(mac)",
            "\(base)/get.php?mac=\(mac)&type=m3u",
            "\(base)/server/load.php?type=itv&action=create_link&mac=\(mac)"
        ]

        for urlCandidate in directM3UUrls {
            if let channels = try? await fetchAndParse(from: urlCandidate), !channels.isEmpty {
                return channels
            }
        }

        // Thử Handshake theo chuẩn Ministra / Stalker Portal MAG
        let cleanMac = mac.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let handshakeUrl = URL(string: "\(base)/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml") else {
            throw URLError(.badURL)
        }

        var hsRequest = URLRequest(url: handshakeUrl)
        hsRequest.timeoutInterval = 20
        hsRequest.setValue("Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 MAG250", forHTTPHeaderField: "User-Agent")
        hsRequest.setValue("mac=\(cleanMac); stb_lang=en; timezone=GMT", forHTTPHeaderField: "Cookie")

        let (hsData, _) = try await URLSession.shared.data(for: hsRequest)
        guard let hsJson = try? JSONSerialization.jsonObject(with: hsData) as? [String: Any],
              let js = hsJson["js"] as? [String: Any],
              let token = js["token"] as? String else {
            throw NSError(domain: "StalkerPortal", code: 401, userInfo: [NSLocalizedDescriptionKey: "Không thể bắt tay (Handshake) với Stalker Portal. Kiểm tra địa chỉ MAC và URL."])
        }

        // Lấy danh sách kênh
        guard let chUrl = URL(string: "\(base)/server/load.php?type=itv&action=get_all_channels&JsHttpRequest=1-xml") else {
            throw URLError(.badURL)
        }

        var chRequest = URLRequest(url: chUrl)
        chRequest.timeoutInterval = 30
        chRequest.setValue("Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 MAG250", forHTTPHeaderField: "User-Agent")
        chRequest.setValue("mac=\(cleanMac); stb_lang=en; timezone=GMT; token=\(token)", forHTTPHeaderField: "Cookie")
        chRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (chData, _) = try await URLSession.shared.data(for: chRequest)
        guard let chJson = try? JSONSerialization.jsonObject(with: chData) as? [String: Any],
              let jsData = chJson["js"] as? [String: Any],
              let dataList = jsData["data"] as? [[String: Any]] else {
            throw NSError(domain: "StalkerPortal", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không đọc được danh sách kênh từ Stalker Portal"])
        }

        var channels: [IPTVChannel] = []
        for item in dataList {
            guard let name = item["name"] as? String else { continue }
            let id = item["id"] as? String ?? (item["id"] as? Int).map(String.init) ?? UUID().uuidString
            let cmd = item["cmd"] as? String ?? ""
            let logo = item["logo"] as? String
            let group = item["genres_str"] as? String ?? "Chung"

            // Xử lý link stream từ trường cmd
            var streamUrl = cmd
            if streamUrl.hasPrefix("ffmpeg ") {
                streamUrl = String(streamUrl.dropFirst("ffmpeg ".count))
            } else if streamUrl.hasPrefix("auto ") {
                streamUrl = String(streamUrl.dropFirst("auto ".count))
            }

            if !streamUrl.isEmpty {
                channels.append(IPTVChannel(
                    id: id,
                    name: name,
                    streamUrl: streamUrl,
                    logoUrl: logo,
                    groupTitle: group,
                    httpHeaders: [
                        "User-Agent": "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 MAG250",
                        "Cookie": "mac=\(cleanMac); token=\(token)"
                    ]
                ))
            }
        }

        if channels.isEmpty {
            throw NSError(domain: "StalkerPortal", code: 404, userInfo: [NSLocalizedDescriptionKey: "Portal không trả về kênh phát nào khả dụng."])
        }

        return channels
    }
}
