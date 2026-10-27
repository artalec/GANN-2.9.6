import SwiftUI
import AppKit

/// Главное окно.
///
/// Раскладка:
///   слева  — список плейлистов
///   справа — waveform с маркерами обрезки, панель управления, список треков
struct ContentView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            if model.isSidebarVisible {
                PlaylistSidebar()
                    .frame(minWidth: 210, idealWidth: 250, maxWidth: 340)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Когда список плейлистов скрыт, этот блок остаётся единственным
            // в HSplitView и занимает всё окно.
            VStack(spacing: 0) {
                WaveformPanel(engine: model.audioEngine)
                Divider()
                TrackList()
                Divider()
                TrackInfoBar()
            }
            .frame(minWidth: 620)
            // Кнопка возврата списка: у левого края окна, по центру высоты.
            .overlay(alignment: .leading) {
                if !model.isSidebarVisible {
                    SidebarToggleButton(
                        systemName: "chevron.right",
                        help: "Показать список плейлистов",
                        action: { model.toggleSidebar() }
                    )
                }
            }
        }
        .frame(minWidth: 880, minHeight: 640)
        .animation(.easeInOut(duration: 0.2), value: model.isSidebarVisible)
    }
}

/// Кнопка скрытия и показа списка плейлистов: стрелка на границе области.
struct SidebarToggleButton: View {

    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 42)
                // RoundedRectangle, а не UnevenRoundedRectangle: последний появился
                // только в macOS 14, а проект собирается под macOS 13.
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(radius: 1)
                )
                .opacity(isHovering ? 1.0 : 0.75)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Верхняя часть: информация, waveform, управление

private struct WaveformPanel: View {

    @EnvironmentObject private var model: AppModel
    /// Движок подписан напрямую: курсор меняется 20 раз в секунду, и перерисовывать
    /// из-за него всё окно не нужно.
    @ObservedObject var engine: AudioEngine

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                trackInfo
                Spacer(minLength: 8)
                effectControls
            }

            WaveformView(
                peaks: model.displayedWaveform,
                currentTime: progressTime,
                duration: displayedDuration,
                accent: displayedAccent,
                trimStart: displayedTrimStart,
                trimEnd: displayedTrimEnd,
                onSeek: { time, shouldPlay, crossfade in
                    model.seekDisplayed(to: time, thenPlay: shouldPlay, crossfade: crossfade)
                },
                onTrimChange: { start, end in
                    guard let track = model.displayedTrack else { return }
                    model.setTrim(for: track.id, start: start, end: end)
                }
            )
            .frame(height: 96)

            transportBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Данные для waveform

    private var displayedTrack: Track? { model.displayedTrack }

    private var displayedDuration: TimeInterval {
        displayedTrack?.duration ?? 0
    }

    private var displayedTrimStart: TimeInterval {
        displayedTrack?.trimStart ?? 0
    }

    private var displayedTrimEnd: TimeInterval {
        guard let track = displayedTrack else { return 0 }
        return track.trimEnd ?? track.duration
    }

    private var displayedAccent: RGBAColor {
        displayedTrack.map { model.accentColor(for: $0) } ?? RGBAColor(red: 0.2, green: 0.55, blue: 1.0)
    }

    /// Время для курсора: если играет этот трек — реальное, если это выбранный,
    /// но не играющий трек — сохранённая точка старта, иначе 0.
    private var progressTime: TimeInterval {
        guard let track = displayedTrack else { return 0 }
        if engine.currentTrack?.id == track.id {
            return engine.currentTime
        }
        return model.pendingStart(for: track.id)
    }

    // MARK: Информация о треке

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let track = displayedTrack {
                Text(track.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(engine.currentTrack?.id == track.id
                         ? engine.currentTime.timecode
                         : track.trimStart.timecode)
                    Text("/")
                    Text(track.effectiveDuration.timecode)

                    if engine.isTransitioning {
                        Text("· переход…").foregroundStyle(Color.orange)
                    }
                    if track.trimStart > 0 || track.trimEnd != nil {
                        Text("· Start \(track.trimStart.timecode)  End \((track.trimEnd ?? track.duration).timecode)")
                            .foregroundStyle(Color.cyan)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            } else {
                Text("Ничего не выбрано")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Выберите трек в списке")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 80, maxWidth: 340, alignment: .leading)
    }

    // MARK: Эффекты

    private var effectControls: some View {
        HStack(alignment: .top, spacing: 12) {
            // Focus Fade — слева от Crossfade.
            effectBlock(
                title: "Focus Fade",
                isOn: Binding(
                    get: { model.state.settings.focusFadeEnabled },
                    set: { value in model.updateSettings { $0.focusFadeEnabled = value } }
                ),
                help: "Плавно останавливает воспроизведение при переходе в другую программу и плавно возобновляет его при возвращении к плееру"
            ) {
                sliderRow(label: "время",
                          value: model.state.settings.focusFadeDuration,
                          range: 0.2...10,
                          enabled: model.state.settings.focusFadeEnabled) { value in
                    model.updateSettings { $0.focusFadeDuration = value }
                }
            }

            Divider().frame(height: 44)

            effectBlock(
                title: "Crossfade",
                isOn: Binding(
                    get: { model.state.settings.crossfadeEnabled },
                    set: { value in model.updateSettings { $0.crossfadeEnabled = value } }
                ),
                help: "Плавный переход между треками"
            ) {
                sliderRow(label: "переход",
                          value: model.state.settings.crossfadeDuration,
                          range: 0.5...15,
                          enabled: model.state.settings.crossfadeEnabled) { value in
                    model.updateSettings { $0.crossfadeDuration = value }
                }
            }

            Divider().frame(height: 44)

            effectBlock(
                title: "High-cut",
                isOn: Binding(
                    get: { model.state.settings.highCutEnabled },
                    set: { value in model.updateSettings { $0.highCutEnabled = value } }
                ),
                help: "Плавно уводит верхи у играющего трека, затем запускает следующий"
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    sliderRow(label: "эффект",
                              value: model.state.settings.highCutDuration,
                              range: 0.3...10,
                              enabled: model.state.settings.highCutEnabled) { value in
                        model.updateSettings { $0.highCutDuration = value }
                    }

                    sliderRow(label: "пауза",
                              value: model.state.settings.highCutPauseAfter,
                              range: 0...10,
                              enabled: model.state.settings.highCutEnabled) { value in
                        model.updateSettings { $0.highCutPauseAfter = value }
                    }
                }
            }
        }
        // Блоки не сжимаются и не переносятся: размер задан внутри effectBlock.
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    /// Строка регулятора. Размеры фиксированы, текст не переносится:
    /// блоки эффектов должны выглядеть одинаково при любом размере окна.
    private func sliderRow(label: String,
                           value: Double,
                           range: ClosedRange<Double>,
                           enabled: Bool,
                           onChange: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 40, alignment: .leading)

            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range)
                .frame(width: 62)
                .controlSize(.mini)
                .disabled(!enabled)

            Text(String(format: "%.1f", value))
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 25, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Один блок эффекта: заголовок и регуляторы. Ширина фиксирована, поэтому
    /// при сжатии окна блок не сжимается и название не пропадает.
    private func effectBlock<Content: View>(title: String,
                                            isOn: Binding<Bool>,
                                            help: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help(help)

            content()
        }
        .frame(width: 138, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Панель управления и громкость

    /// Нижняя панель: четыре блока делят ширину поровну, разделители фиксированы.
    private var transportBar: some View {
        HStack(spacing: 0) {
            transportButtons
                .frame(maxWidth: .infinity)
            Divider().frame(height: 22)
            playlistModeButtons
                .frame(maxWidth: .infinity)
            Divider().frame(height: 22)
            volumeControl
                .frame(maxWidth: .infinity)
            Divider().frame(height: 22)
            deviceControl
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    /// Предыдущий / Играть-пауза / Пауза / Следующий / Стоп.
    private var transportButtons: some View {
        HStack(spacing: 8) {
            Button {
                model.playPrevious()
            } label: {
                Image(systemName: "backward.fill").frame(width: 20)
            }
            .help("Предыдущий трек")

            Button {
                playSelectedOrResume()
            } label: {
                Image(systemName: "play.fill").frame(width: 22)
            }
            .help("Воспроизвести выделенный или возобновить (Пробел)")

            Button {
                engine.pause()
            } label: {
                Image(systemName: "pause.fill").frame(width: 22)
            }
            .help("Пауза")
            .disabled(!engine.isPlaying)

            Button {
                model.playNext()
            } label: {
                Image(systemName: "forward.fill").frame(width: 20)
            }
            .help("Следующий трек")

            Button {
                engine.stop()
            } label: {
                Image(systemName: "stop.fill").frame(width: 20)
            }
            .help("Стоп (Esc)")
        }
        .buttonStyle(.borderless)
    }

    /// Три режима плейлиста: повтор трека, зацикливание плейлиста, автопереход.
    private var playlistModeButtons: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { model.state.settings.loopTrackEnabled },
                set: { value in model.updateSettings { $0.loopTrackEnabled = value } }
            )) {
                Image(systemName: "repeat.1")
            }
            .toggleStyle(.button)
            .help("Зациклить текущий трек")

            Toggle(isOn: Binding(
                get: { model.selectedPlaylist?.loopEnabled ?? false },
                set: { model.setLoopPlaylist($0) }
            )) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Зациклить плейлист")

            Toggle(isOn: Binding(
                get: { model.selectedPlaylist?.autoplayEnabled ?? false },
                set: { model.setAutoplay($0) }
            )) {
                Image(systemName: "arrow.forward.to.line")
            }
            .toggleStyle(.button)
            .help("Автоматически переходить к следующему треку")
        }
    }

    /// Громкость: иконка, ползунок (растягивается), проценты.
    private var volumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: volumeIcon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Slider(value: Binding(
                get: { model.state.settings.volume },
                set: { model.setVolume($0) }
            ), in: 0...1)
            .controlSize(.small)
            .frame(maxWidth: .infinity)

            Text("\(Int(model.state.settings.volume * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    /// Выбор устройства вывода: значок колонки и список стоят вплотную, с небольшим отступом.
    /// Группа центрируется в своём блоке и ширину списка ограничивает, поэтому при изменении
    /// размера окна значок не отходит от списка.
    private var deviceControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Picker("", selection: Binding(
                get: { model.outputDeviceSelection },
                set: { model.setOutputDevice($0) }
            )) {
                Text("Системное по умолчанию").tag(Optional<String>.none)
                ForEach(model.outputDevices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(minWidth: 110, maxWidth: 190)
            .help("Устройство, через которое играет плеер")
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }

    /// Запускает выделенный трек, иначе возобновляет текущий или запускает первый.
    private func playSelectedOrResume() {
        if let playlist = model.selectedPlaylist, !model.selection.isEmpty,
           let first = model.selection.selectedTracks(from: playlist.tracks).first {
            model.play(track: first)
            return
        }
        if engine.currentTrack != nil {
            engine.resume()
        } else {
            model.playFirstTrackOfSelectedPlaylist()
        }
    }

    private var volumeIcon: String {
        let v = model.state.settings.volume
        if v <= 0.001 { return "speaker.slash.fill" }
        if v < 0.4 { return "speaker.fill" }
        if v < 0.75 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
