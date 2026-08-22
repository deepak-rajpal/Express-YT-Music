import Foundation

/// Appends to ~/Library/Logs/ExpressYTMusic.log so navigation problems can be
/// diagnosed after the fact. Local file only - nothing is transmitted anywhere.
enum Diagnostics {

    private static let queue = DispatchQueue(label: "eym.diagnostics")
    private static let maxBytes = 512 * 1024

    static var logURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        return logs.appendingPathComponent("ExpressYTMusic.log")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func log(_ message: String) {
        NSLog("[ExpressYTMusic] %@", message)
        queue.async {
            let line = "\(formatter.string(from: Date()))  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let url = logURL

            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)

            // Keep the file from growing without bound.
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > maxBytes {
                try? fm.removeItem(at: url)
            }

            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
