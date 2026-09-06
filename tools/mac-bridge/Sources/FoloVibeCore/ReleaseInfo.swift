import Foundation

/// A release published on GitHub, reduced to what an updater needs.
public struct ReleaseInfo: Equatable {
    public var tag: String
    public var version: String
    public var appURL: URL?
    public var firmwareURL: URL?

    public init(tag: String, version: String, appURL: URL?, firmwareURL: URL?) {
        self.tag = tag
        self.version = version
        self.appURL = appURL
        self.firmwareURL = firmwareURL
    }

    /// Strips the tag down to comparable digits: `v0.3.3-vibe-typeless` -> `0.3.3`.
    public static func version(fromTag tag: String) -> String {
        var s = tag
        if s.hasPrefix("v") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[s.startIndex..<dash]) }
        return s
    }

    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = obj["tag_name"] as? String
        else { return nil }
        var app: URL?
        var firmware: URL?
        for asset in obj["assets"] as? [[String: Any]] ?? [] {
            guard let name = asset["name"] as? String,
                let raw = asset["browser_download_url"] as? String,
                let url = URL(string: raw)
            else { continue }
            if name.hasSuffix(".zip") { app = url }
            if name.hasSuffix(".bin") { firmware = url }
        }
        return ReleaseInfo(
            tag: tag, version: version(fromTag: tag), appURL: app, firmwareURL: firmware)
    }
}

/// Compares dotted numeric versions. Anything unparsable sorts lowest so a
/// malformed local version never blocks an upgrade.
public func versionIsNewer(_ candidate: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.split(whereSeparator: { $0 == "." || $0 == "-" })
            .prefix(4)
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
    let a = parts(candidate), b = parts(current)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}
