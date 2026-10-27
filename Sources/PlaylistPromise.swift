import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Отложенное копирование плейлиста (NSFilePromiseProvider).
///
/// Перетаскивание начинается сразу, без копирования. Когда пользователь бросает плейлист
/// в Finder, система передаёт папку назначения, и только тогда треки копируются прямо туда.
/// Временных копий нет, поэтому место не расходуется дважды, а при отмене ничего не копируется.
final class PlaylistPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {

    private let name: String
    private let sources: [URL]

    /// Очередь, на которой выполняется копирование: не на главном потоке.
    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "GANNPlayer.playlist-promise"
        q.qualityOfService = .userInitiated
        return q
    }()

    init(name: String, sources: [URL]) {
        self.name = name
        self.sources = sources
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        PlaylistCopier.sanitized(name)
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.queue
    }

    /// Вызывается, когда Finder получил папку назначения. url — это путь будущей папки плейлиста.
    func filePromiseProvider(_ provider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        let parent = url.deletingLastPathComponent()
        let folder = Self.freeFolderURL(in: parent, preferred: url.lastPathComponent)
        do {
            let report = try PlaylistCopier.copy(sources: sources, into: folder)
            if report.failed > 0 {
                // Папка уже создана; сообщаем Finder, что часть треков не скопировалась.
                let error = NSError(
                    domain: "GANNPlayer.PlaylistCopy", code: report.failed,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Не удалось скопировать треков: \(report.failed) из \(sources.count) в «\(name)»."])
                completionHandler(error)
            } else {
                completionHandler(nil)
            }
        } catch {
            completionHandler(error)
        }
    }

    /// Имя папки в месте назначения. Если такая папка уже есть, добавляем « 2», « 3» и т.д.
    private static func freeFolderURL(in parent: URL, preferred: String) -> URL {
        let fm = FileManager.default
        var candidate = parent.appendingPathComponent(preferred, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(preferred) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}

/// Провайдер перетаскивания плейлиста: file promise для Finder плюс обычный текст.
///
/// Строки плейлистов принимают только `.plainText` и `.fileURL`, а file promise кладёт в буфер
/// собственные типы. Без текста SwiftUI не считал бы такое перетаскивание подходящим, и
/// перестановка плейлистов внутри панели не срабатывала. Текст нужен только для этого;
/// Finder берёт из буфера file promise.
final class PlaylistPromiseProvider: NSFilePromiseProvider {

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(.string)
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .string { return "playlist" }
        return super.pasteboardPropertyList(forType: type)
    }
}

/// Источник перетаскивания поверх строки плейлиста.
///
/// Перехватывает только левую кнопку мыши. Короткий щелчок — выбор плейлиста,
/// протягивание — сессия перетаскивания с file promise. Правая кнопка и колёсико
/// пропускаются к SwiftUI, а события после нажатия остаются у этого вида, поэтому
/// зоны сброса (drop) строк работают как раньше.
struct PlaylistDragSource: NSViewRepresentable {

    let playlist: Playlist
    let onClick: () -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> PlaylistDragNSView {
        let view = PlaylistDragNSView()
        view.configure(playlist: playlist, onClick: onClick, onBegin: onBegin, onEnd: onEnd)
        return view
    }

    func updateNSView(_ view: PlaylistDragNSView, context: Context) {
        view.configure(playlist: playlist, onClick: onClick, onBegin: onBegin, onEnd: onEnd)
    }
}

final class PlaylistDragNSView: NSView, NSDraggingSource {

    private var playlist: Playlist?
    private var onClick: () -> Void = {}
    private var onBegin: () -> Void = {}
    private var onEnd: () -> Void = {}
    private var downEvent: NSEvent?
    private var didDrag = false
    private var promiseDelegate: PlaylistPromiseDelegate?

    func configure(playlist: Playlist, onClick: @escaping () -> Void,
                   onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.playlist = playlist
        self.onClick = onClick
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    /// Вид перехватывает только нажатие левой кнопки. Остальные события идут дальше, как без него.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let down = downEvent, let playlist else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard abs(dx) + abs(dy) > 4 else { return }
        didDrag = true

        let sources = playlist.tracks.map { $0.url }
        let delegate = PlaylistPromiseDelegate(name: playlist.name, sources: sources)
        let provider = PlaylistPromiseProvider(fileType: UTType.folder.identifier, delegate: delegate)
        // Держим делегат сильной ссылкой: провайдер не владеет им, а копирование
        // вызывается позже, уже после начала перетаскивания.
        promiseDelegate = delegate

        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: snapshot())

        onBegin()
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        // Щелчок без протягивания — выбор плейлиста.
        if !didDrag { onClick() }
        downEvent = nil
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // .move нужен для перестановки плейлистов внутри приложения, .copy — для Finder.
        [.copy, .move]
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        DispatchQueue.main.async { [onEnd] in onEnd() }
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }
}
