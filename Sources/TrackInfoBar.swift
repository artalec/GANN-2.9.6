import SwiftUI
import AVFoundation

/// Технические параметры файла трека.
struct TrackTechInfo: Equatable {
    let bitrateKbps: Int?
    let sampleRate: Double?
    let channels: Int?
    let sizeBytes: Int64?
}

/// Читает параметры файла. Вызывать вне главного потока.
enum TrackTechLoader {

    static func load(url: URL) async -> TrackTechInfo {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return TrackTechInfo(bitrateKbps: nil, sampleRate: nil, channels: nil, sizeBytes: nil)
        }

        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value

        var sampleRate: Double?
        var channels: Int?
        var duration: Double = 0
        if let file = try? AVAudioFile(forReading: url) {
            let format = file.processingFormat
            sampleRate = format.sampleRate
            channels = Int(format.channelCount)
            if format.sampleRate > 0 {
                duration = Double(file.length) / format.sampleRate
            }
        }

        // Битрейт из заголовка аудиодорожки. Если его нет (WAV, AIFF), считаем по размеру и длительности.
        var bitrate: Int?
        let asset = AVURLAsset(url: url)
        if let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let rate = try? await track.load(.estimatedDataRate), rate > 0 {
            bitrate = Int((Double(rate) / 1000).rounded())
        }
        if bitrate == nil, let size, duration > 0 {
            bitrate = Int((Double(size) * 8 / duration / 1000).rounded())
        }

        return TrackTechInfo(bitrateKbps: bitrate, sampleRate: sampleRate,
                             channels: channels, sizeBytes: size)
    }
}

/// Нижняя строка окна: параметры выделенного трека (или играющего, если ничего не выделено).
struct TrackInfoBar: View {

    @EnvironmentObject private var model: AppModel
    @State private var info: TrackTechInfo?

    /// Ключ для перезагрузки: меняется при выборе другого трека или замене файла.
    private var taskKey: String {
        guard let track = model.displayedTrack else { return "" }
        return "\(track.id.uuidString)|\(track.path)"
    }

    var body: some View {
        HStack(spacing: 14) {
            if let track = model.displayedTrack {
                Text(track.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)

                if let info, info.sizeBytes != nil {
                    item("Битрейт", info.bitrateKbps.map { "\($0) kbps" } ?? "—")
                    item("Частота", info.sampleRate.map { String(format: "%.1f kHz", $0 / 1000) } ?? "—")
                    item("Каналы", channelsText(info.channels))
                    item("Размер", info.sizeBytes.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    } ?? "—")
                } else if info != nil {
                    Text("файл не найден").foregroundStyle(Color.red)
                } else {
                    Text("загрузка…").foregroundStyle(.secondary)
                }
            } else {
                Text("Трек не выбран").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: taskKey) {
            info = nil
            guard let track = model.displayedTrack else { return }
            let url = track.url
            let loaded = await Task.detached(priority: .utility) {
                await TrackTechLoader.load(url: url)
            }.value
            if !Task.isCancelled { info = loaded }
        }
    }

    private func item(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func channelsText(_ n: Int?) -> String {
        switch n {
        case .none: return "—"
        case 1: return "моно"
        case 2: return "стерео"
        case .some(let v): return "\(v) кан."
        }
    }
}
