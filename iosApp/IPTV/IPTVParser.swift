import Foundation

public final class IPTVParser {

    public static let shared = IPTVParser()

    private init() {}

    /// Phân tích nội dung văn bản M3U/M3U8 thành danh sách IPTVChannel
    public func parse(m3uContent: String) -> [IPTVChannel] {
        var channels: [IPTVChannel] = []

        // Chuẩn hóa dòng
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
                // Reset metadata trước đó nếu có
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
                // Header theo chuẩn VLC: #EXTVLCOPT:http-user-agent=...
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
                // DRM metadata theo chuẩn Kodi / TiviMate
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
                // Đây là đường dẫn URL phát
                var streamUrl = line

                // Kiểm tra định dạng url|Header=...&Header2=...
                if let pipeIndex = streamUrl.firstIndex(of: "|") {
                    let headerPart = String(streamUrl[streamUrl.index(after: pipeIndex)...])
                    streamUrl = String(streamUrl[..<pipeIndex])

                    // Tách header
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

    /// Trích xuất các thuộc tính từ dòng `#EXTINF:`
    private func parseExtInf(
        line: String,
        name: inout String,
        logo: inout String?,
        group: inout String,
        tvgId: inout String?,
        tvgName: inout String?
    ) {
        // Tách phần tên kênh (sau dấu phẩy cuối cùng)
        if let commaIndex = line.lastIndex(of: ",") {
            let channelName = String(line[line.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
            name = channelName
        } else {
            name = "Kênh"
        }

        // Trích xuất các attribute dạng key="value"
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

    /// Tải và phân tích từ link URL từ xa
    public func fetchAndParse(from urlString: String) async throws -> [IPTVChannel] {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
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
}
