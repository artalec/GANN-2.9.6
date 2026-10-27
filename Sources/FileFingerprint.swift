import Foundation
import CryptoKit

/// Отпечаток файла: размер в байтах и SHA-256 содержимого.
///
/// Файл читается кусками по 1 МБ, поэтому даже большой трек не загружает
/// память целиком. Вызывать из фонового потока — на длинных файлах это секунды.
struct FileFingerprint: Equatable {
    let size: Int64
    let sha256: String

    static func compute(path: String) -> FileFingerprint? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            // На конце файла read(upToCount:) возвращает nil (а не пустые данные).
            // Раньше nil принимался за ошибку, и отпечаток не считался ни для одного файла.
            // Ошибку чтения ловим отдельно, конец файла — выход из цикла.
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 1 << 20)
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            total += Int64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(size: total, sha256: digest)
    }
}
