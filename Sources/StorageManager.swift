import Foundation

/// Сохранение состояния приложения и экспорт/импорт плейлистов.
struct StorageManager {

    static let shared = StorageManager()

    private let fileManager = FileManager.default

    private var directory: URL {
        Self.appSupportDirectory()
    }

    /// Папка данных приложения: ~/Library/Application Support/GANN Player.
    /// Одноразово копирует appstate.json и recovery.log из старой папки DJPlayer,
    /// чтобы плейлисты и журнал не пропали после переименования.
    static func appSupportDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("GANN Player", isDirectory: true)
        let legacy = base.appendingPathComponent("DJPlayer", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: legacy.path) {
            for name in ["appstate.json", "recovery.log"] {
                let src = legacy.appendingPathComponent(name)
                let dst = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }
        return dir
    }

    private var stateURL: URL {
        directory.appendingPathComponent("appstate.json")
    }

    /// Резервная копия последнего успешно прочитанного состояния. Обновляется
    /// прямо перед тем, как write() перезапишет appstate.json — то есть в
    /// любой момент содержит версию, которая гарантированно декодировалась.
    private var backupURL: URL {
        directory.appendingPathComponent("appstate.backup.json")
    }

    // Путь можно вывести в консоль для отладки.
    var statePath: String { stateURL.path }

    // MARK: - Состояние приложения

    private static let writeQueue = DispatchQueue(label: "GANNPlayer.storage", qos: .utility)

    /// Синхронная запись. Ждёт завершения фоновых записей, поэтому порядок сохраняется
    /// и последнее состояние (например, при выходе) гарантированно попадает на диск.
    func save(_ state: AppState) {
        Self.writeQueue.sync { self.write(state) }
    }

    /// Фоновая запись для автосохранения: кодирование JSON не блокирует интерфейс.
    func saveInBackground(_ state: AppState) {
        Self.writeQueue.async { self.write(state) }
    }

    private func write(_ state: AppState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)

            // Перед перезаписью сохраняем текущий файл как бэкап — если он
            // существует и валиден. Так один сбойный autosave не уничтожает
            // последнее хорошее состояние: откатиться есть куда (см. load()).
            backupCurrentFileIfValid()

            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("GANN Player: не удалось сохранить состояние — \(error.localizedDescription)")
        }
    }

    /// Копирует appstate.json в appstate.backup.json, только если текущий файл
    /// сам успешно декодируется и содержит хотя бы один плейлист. Это не даёт
    /// бэкапу тоже стать пустым/битым вслед за основным файлом.
    private func backupCurrentFileIfValid() {
        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data),
              !state.playlists.isEmpty else { return }
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.copyItem(at: stateURL, to: backupURL)
    }

    func load() -> AppState {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return loadBackupOrFresh(reason: "appstate.json отсутствует")
        }
        do {
            let data = try Data(contentsOf: stateURL)
            let state = try JSONDecoder().decode(AppState.self, from: data)
            guard !state.playlists.isEmpty else {
                return loadBackupOrFresh(reason: "appstate.json декодирован, но плейлистов нет")
            }
            return state
        } catch {
            NSLog("GANN Player: не удалось прочитать состояние — \(error.localizedDescription)")
            return loadBackupOrFresh(reason: "appstate.json повреждён: \(error.localizedDescription)")
        }
    }

    /// Последняя линия обороны перед AppState.fresh(): пробуем резервную копию,
    /// прежде чем решить, что у пользователя и правда пустая библиотека.
    private func loadBackupOrFresh(reason: String) -> AppState {
        NSLog("GANN Player: \(reason), пробую appstate.backup.json")
        guard fileManager.fileExists(atPath: backupURL.path),
              let data = try? Data(contentsOf: backupURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data),
              !state.playlists.isEmpty else {
            NSLog("GANN Player: бэкап недоступен или тоже пуст — начинаю с чистого состояния")
            return AppState.fresh()
        }
        NSLog("GANN Player: состояние восстановлено из appstate.backup.json")
        // Чиним основной файл сразу, чтобы следующий запуск не зависел от бэкапа.
        try? data.write(to: stateURL, options: .atomic)
        return state
    }

    // MARK: - Экспорт / импорт плейлистов

    func export(_ playlist: Playlist, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(playlist)
        try data.write(to: url, options: .atomic)
    }

    func `import`(from url: URL) throws -> Playlist {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Playlist.self, from: data)
    }

    func resetAll() {
        try? fileManager.removeItem(at: stateURL)
        try? fileManager.removeItem(at: backupURL)
    }
}
