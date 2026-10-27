import SwiftUI
import AppKit

/// Waveform трека: клик для перемотки, перетаскиваемые маркеры Start Time / End Time.
///
/// Маркеры выглядят как серые треугольники по краям области обрезки.
/// Значения сохраняются в модели трека и применяются при следующих запусках.
struct WaveformView: View {

    let peaks: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let accent: RGBAColor

    /// Точки обрезки в секундах от начала файла.
    let trimStart: TimeInterval
    let trimEnd: TimeInterval

    /// Перемотка: (позиция относительно trimStart, нужно ли запускать воспроизведение).
    /// Клик не запускает, протягивание запускает.
    /// (позиция, играть ли, плавный переход 0.5 с при клике)
    let onSeek: (TimeInterval, Bool, Bool) -> Void
    let onTrimChange: (TimeInterval, TimeInterval) -> Void

    @State private var draggingHandle: Handle?
    @State private var dragStartX: CGFloat = 0
    @State private var dragStartValues: (start: TimeInterval, end: TimeInterval) = (0, 0)
    /// Значения маркеров во время перетягивания. В движок и модель не уходят до отпускания.
    @State private var preview: (start: TimeInterval, end: TimeInterval)?

    private enum Handle { case start, end }

    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1
    /// Маркеры крупнее на 30 % по сравнению с прежними 14×10 и 22.
    private let handleWidth: CGFloat = 18
    private let handleHeight: CGFloat = 13
    private let handleHitArea: CGFloat = 29

    private var safeDuration: TimeInterval { max(duration, 0.001) }

    /// Что рисовать: во время перетягивания — предпросмотр, иначе сохранённые значения.
    private var shownStart: TimeInterval { preview?.start ?? trimStart }
    private var shownEnd: TimeInterval { preview?.end ?? trimEnd }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.18))

                // Волна, затемнение вне сегмента обрезки и курсор воспроизведения —
                // всё одним Canvas-проходом (см. примечание о производительности ниже).
                Canvas { context, size in
                    drawWaveform(in: context, size: size)
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false)

                if peaks.isEmpty {
                    Text("Выберите трек в списке")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: width, height: height)
                        .allowsHitTesting(false)
                }

                // Маркеры Start / End
                if duration > 0 {
                    trimHandle(.start, width: width, height: height)
                    trimHandle(.end, width: width, height: height)
                }
            }
            .contentShape(Rectangle())
            // Клик или перетаскивание по свободному месту — перемотка
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard draggingHandle == nil, duration > 0 else { return }
                        // Перетаскивание по waveform — плавная перемотка без кроссфейда.
                        let moved = abs(value.location.x - value.startLocation.x) > 3
                        if moved { seekToX(value.location.x, width: width, shouldPlay: true, crossfade: false) }
                    }
                    .onEnded { value in
                        guard draggingHandle == nil, duration > 0 else { return }
                        // Клик — переход к точке; если трек играет, с кроссфейдом 0.5 с.
                        let moved = abs(value.location.x - value.startLocation.x) > 3
                        if !moved { seekToX(value.location.x, width: width, shouldPlay: false, crossfade: true) }
                    }
            )
        }
    }

    // MARK: - Отрисовка (Canvas)

    /// Рисует затемнение вне сегмента обрезки, бары волны и курсор воспроизведения
    /// за один проход.
    ///
    /// РАНЬШЕ: волна строилась как `HStack` из ForEach(RoundedRectangle), то есть
    /// до ~900 отдельных SwiftUI-вьюх (по числу пиков, см. WaveformGenerator.targetPeakCount),
    /// каждая со своей identity, layout-проходом и диффингом. AudioEngine обновляет
    /// `currentTime` таймером 20 раз в секунду, и при каждом тике SwiftUI пересчитывал
    /// played/unplayed цвет для всех баров — то есть сотни view-апдейтов в секунду
    /// ради сдвига курсора на пару пикселей и перекраски горстки баров у границы.
    /// На плейлистах с длинными треками (где видно много баров) это was заметно
    /// на глаз как подвисания при простой перемотке.
    ///
    /// ТЕПЕРЬ: один `Canvas`, который нарисован вручную через `GraphicsContext.fill`.
    /// Бары сгруппированы всего в 3 Path (вне сегмента / внутри, но ещё не сыграно /
    /// уже сыграно), так что на кадр уходит ~5 операций заливки вместо сотен
    /// SwiftUI-вьюх с диффингом. Canvas не хранит дерево дочерних вьюх вообще —
    /// он выполняет draw-замыкание напрямую, поэтому стоимость перерисовки не
    /// зависит от количества баров так, как зависела стоимость ForEach.
    ///
    /// TimelineView здесь намеренно не используется: currentTime и так приходит
    /// снаружи с нужной частотой от AudioEngine, а интерполяция по таймлайну
    /// потребовала бы отдельно синхронизировать условное "время старта" с реальной
    /// позицией движка (seek, пауза, кроссфейд, trim) — риск рассинхронизации
    /// курсора перевешивает выигрыш в плавности.
    private func drawWaveform(in context: GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return }

        let startRatio = min(max(shownStart / safeDuration, 0), 1)
        let endRatio = min(max(shownEnd / safeDuration, 0), 1)
        let playedRatio = min(max((trimStart + currentTime) / safeDuration, 0), 1)

        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width

        // Затемнённые области вне сегмента обрезки
        if startX > 0 {
            context.fill(Path(CGRect(x: 0, y: 0, width: startX, height: height)),
                         with: .color(.black.opacity(0.35)))
        }
        if endX < width {
            context.fill(Path(CGRect(x: endX, y: 0, width: width - endX, height: height)),
                         with: .color(.black.opacity(0.35)))
        }

        if !peaks.isEmpty {
            let capacity = max(1, Int(width / (barWidth + barSpacing)))
            let values = downsample(peaks, to: capacity)

            if !values.isEmpty {
                let denom = Double(max(1, values.count - 1))
                // Три группы баров — вне сегмента, внутри-но-не-сыграно, сыграно —
                // заливаются каждая одним вызовом, а не поштучно.
                var outsidePath = Path()
                var unplayedPath = Path()
                var playedPath = Path()

                for (index, value) in values.enumerated() {
                    let ratio = Double(index) / denom
                    let inSegment = ratio >= startRatio && ratio <= endRatio
                    let played = ratio <= playedRatio

                    let barHeight = max(2, CGFloat(value) * (height - 16))
                    let x = CGFloat(index) * (barWidth + barSpacing)
                    let rect = CGRect(x: x, y: (height - barHeight) / 2, width: barWidth, height: barHeight)
                    let barPath = Path(roundedRect: rect, cornerRadius: 1)

                    if !inSegment {
                        outsidePath.addPath(barPath)
                    } else if played {
                        playedPath.addPath(barPath)
                    } else {
                        unplayedPath.addPath(barPath)
                    }
                }

                context.fill(outsidePath, with: .color(Color.secondary.opacity(0.25)))
                context.fill(unplayedPath, with: .color(accent.swiftUIColor.opacity(0.45)))
                context.fill(playedPath, with: .color(accent.swiftUIColor))
            }
        }

        // Курсор воспроизведения — поверх баров, как и раньше
        if duration > 0 {
            let cursorX = CGFloat(min(max((trimStart + currentTime) / safeDuration, 0), 1)) * width
            let cursorRect = CGRect(x: cursorX - 1, y: 0, width: 2, height: height)
            context.fill(Path(cursorRect), with: .color(.red.opacity(0.9)))
        }
    }

    // MARK: - Позиции

    /// X для времени в файле (0...duration).
    private func xPosition(forFileTime time: TimeInterval, width: CGFloat) -> CGFloat {
        let ratio = min(max(time / safeDuration, 0), 1)
        return CGFloat(ratio) * width
    }

    /// Время в файле для координаты X.
    private func fileTime(forX x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        let ratio = min(max(x / width, 0), 1)
        return Double(ratio) * safeDuration
    }

    /// Перемотка: клик задаёт позицию относительно trimStart.
    private func seekToX(_ x: CGFloat, width: CGFloat, shouldPlay: Bool, crossfade: Bool) {
        let absolute = fileTime(forX: x, width: width)
        let relative = absolute - trimStart
        onSeek(max(0, min(relative, max(0, trimEnd - trimStart))), shouldPlay, crossfade)
    }

    // MARK: - Маркеры обрезки

    /// Серый треугольный маркер, перетаскивается мышью.
    /// Во время перетягивания меняется только предпросмотр. Значение уходит в модель
    /// один раз при отпускании кнопки, поэтому воспроизведение не перезапускается и не сдвигается.
    private func trimHandle(_ handle: Handle, width: CGFloat, height: CGFloat) -> some View {
        let time = handle == .start ? shownStart : shownEnd
        let x = xPosition(forFileTime: time, width: width)

        return ZStack {
            Triangle()
                .fill(Color.gray.opacity(0.95))
                .frame(width: handleWidth, height: handleHeight)
                .overlay(
                    Triangle()
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                        .frame(width: handleWidth, height: handleHeight)
                )
                .offset(y: handle == .start ? -height / 2 + handleHeight / 2 : height / 2 - handleHeight / 2)

            Rectangle()
                .fill(Color.gray.opacity(0.9))
                .frame(width: 1.5, height: height)
        }
        .frame(width: handleHitArea, height: height)
        .contentShape(Rectangle())
        .offset(x: x - handleHitArea / 2)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if draggingHandle == nil {
                        draggingHandle = handle
                        dragStartValues = (trimStart, trimEnd)
                    }
                    let newAbs = fileTime(forX: value.location.x, width: width)

                    switch handle {
                    case .start:
                        // Start не может зайти за End (минимум 0.2 с сегмента)
                        let upper = min(dragStartValues.end, safeDuration)
                        let clamped = max(0, min(newAbs, upper - 0.2))
                        preview = (clamped, dragStartValues.end)
                    case .end:
                        let lower = max(0, dragStartValues.start)
                        let clamped = min(safeDuration, max(newAbs, lower + 0.2))
                        preview = (dragStartValues.start, clamped)
                    }
                }
                .onEnded { _ in
                    if let p = preview, abs(p.start - trimStart) > 0.001 || abs(p.end - trimEnd) > 0.001 {
                        onTrimChange(p.start, p.end)
                    }
                    preview = nil
                    draggingHandle = nil
                }
        )
        .help(handle == .start ? "Start Time — потяните, чтобы задать начало" : "End Time — потяните, чтобы задать конец")
    }

    private func downsample(_ source: [Float], to count: Int) -> [Float] {
        guard !source.isEmpty, count > 0 else { return [] }
        if source.count <= count { return source }

        var result: [Float] = []
        result.reserveCapacity(count)
        let ratio = Double(source.count) / Double(count)

        for i in 0..<count {
            let start = Int(Double(i) * ratio)
            let end = min(source.count, max(start + 1, Int(Double(i + 1) * ratio)))
            var peak: Float = 0
            for j in start..<end { peak = max(peak, source[j]) }
            result.append(peak)
        }
        return result
    }
}

/// Треугольник для маркеров обрезки.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
