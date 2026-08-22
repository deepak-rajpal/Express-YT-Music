import Foundation

/// Decides whether a host belongs to Google/YouTube.
///
/// Used for two things: keeping the whole sign-in and channel-picker flow inside the
/// app (it bounces through many Google hosts), and sending everything else to the
/// user's real browser. Because it gates what may load in a window holding a live
/// YouTube session, look-alike hostnames must not match - see Tools/hosttest.swift.
enum FirstPartyHosts {

    /// Bases we accept, followed by a TLD or a two-part country TLD
    /// (`google.com`, `google.co.in`, `youtube.de`, ...). The leading `(^|\.)`
    /// anchors the base to a label boundary, so `notgoogle.com` cannot match, and the
    /// trailing `$` stops `google.com.example.net` from matching.
    private static let pattern = try! NSRegularExpression(
        pattern: "(^|\\.)(google|youtube|youtu|googleapis|googleusercontent|ggpht|gstatic"
               + "|googlevideo|ytimg|withgoogle|gvt1|gvt2)\\.([a-z]{2,3}\\.)?[a-z]{2,}$",
        options: .caseInsensitive
    )

    static func matches(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : host
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return pattern.firstMatch(in: trimmed, range: range) != nil
    }
}
