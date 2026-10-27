import Foundation

/// Копирование треков плейлиста в папку назначения.
///
/// Используется при отложенном копировании (file promise): папка создаётся
/// напрямую в месте, куда пользователь бросил плейлист в Finder. Временных копий нет.
///
/// Правила (не меняются):
/// - Папка называется как плейлист; символы «/» и «:» заменяются на «-».
/// - Одинаковые имена файлов не перезаписываются: «Song.mp3», затем «Song 2.mp3».
/// - Трек, чей файл пропал, пропускается; об этом пишется в журнал.
enum PlaylistCopier {

    struct Report {
        /// Сколько треков скопировано.
        var copied = 0
        /// Сколько треков пропущено, потому что файл не найден.
        var missing = 0
        /// Сколько треков не удалось скопировать из-за ошибки записи.
        var failed = 0
        /// Первая ошибка записи, для сообщения пользователю.
        var firstError: Error?
    }

    /// Создаёт папку `destination` и копирует в неё файлы из `sources`.
    /// Ошибка создания самой папки пробрасывается наверх; ошибки отдельных файлов — в отчёте.
    static func copy(sources: [URL], into destination: URL) throws -> Report {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var report = Report()
        var used = Set<String>()
        for source in sources {
            guard fm.fileExists(atPath: source.path) else {
                report.missing += 1
                NSLog("GANN Player: трек не скопирован, файл не найден — \(source.path)")
                continue
            }
            let name = uniqueName(for: source.lastPathComponent, used: &used)
            do {
                try fm.copyItem(at: source, to: destination.appendingPathComponent(name))
                report.copied += 1
            } catch {
                report.failed += 1
                if report.firstError == nil { report.firstError = error }
                NSLog("GANN Player: не удалось скопировать \(source.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Имя папки без символов, которые нельзя использовать в пути macOS.
    static func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Плейлист" : cleaned
    }

    /// «Song.mp3», а при совпадении имён — «Song 2.mp3», «Song 3.mp3» и т.д.
    static func uniqueName(for fileName: String, used: inout Set<String>) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = fileName
        var n = 2
        while used.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
