import AppKit
import Observation
import SwiftUI

/// Default fallback module — used as the open-pill content when nothing else
/// (Tray, Music) is active. **Reports `isActive == false`** so it does not
/// surface itself in the closed pill: by default the closed state stays as
/// the bare physical notch and the user reveals the clock by hovering.
///
/// Open layout: time + date on the left; optional camera mirror on the right
/// after an explicit click (camera never starts until then).
@Observable
@MainActor
final class ClockModule: NotchModule {
    let id           = "clock"
    let title        = "Time"
    let iconName     = "clock"
    let supportsDrop = false

    /// Intentionally `false` — the clock is a "peek on hover" module, not a
    /// permanent fixture in the menu bar.
    var isActive: Bool { false }

    /// The open view already shows a big time + full date — we don't want a
    /// redundant tiny copy stuck above it.
    var showsClosedHeaderInOpen: Bool { false }

    /// Matches `NotchSizing.openSize.width` so the open pill uses the full canvas width.
    var openExpandedWidth: CGFloat { NotchSizing.openSize.width }

    let mirrorCapture = NotchMirrorCapture()

    var openView: AnyView { AnyView(ClockOpenView(clock: self)) }
}

// MARK: - Formatters (cached — DateFormatter is expensive to construct)

private enum ClockFormat {
    /// Full weekday + day + month name, e.g. `Monday, 11 May`.
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()
}

// MARK: - Open view

private enum ClockNotchLayout {
    /// 1:1 mirror preview / gate tap target (points).
    static let mirrorSquare: CGFloat = 176
    /// Center column for the month grid (points).
    static let calendarWidth: CGFloat = 152
    static let dividerWidth: CGFloat = 1
}

private struct NotchClockDivider: View {
    let maxHeight: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.02),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: ClockNotchLayout.dividerWidth)
            .frame(maxHeight: maxHeight)
    }
}

private enum WeekendTint: Equatable {
    case saturday
    case sunday

    var color: Color {
        switch self {
        case .saturday: return Color(red: 0.48, green: 0.72, blue: 1.0)
        case .sunday:   return Color(red: 1.0, green: 0.42, blue: 0.52)
        }
    }
}

/// Compact month grid for the center of the open clock notch.
private struct NotchMiniCalendar: View {
    let now: Date

    private var calendar: Calendar { .current }

    private static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f
    }()

    var body: some View {
        VStack(spacing: 6) {
            Text(Self.monthTitle.string(from: now))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let wd = weekdayForGridColumn(i)
                    Text(weekdayHeader(i))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(weekendTint(weekday: wd)?.color ?? .white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 12), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(dayCells(), id: \.id) { cell in
                    if let d = cell.day {
                        Text("\(d)")
                            .font(.system(size: 10, weight: cell.isToday ? .bold : .regular, design: .rounded))
                            .foregroundStyle(dayNumberColor(cell))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background {
                                if cell.isToday {
                                    Circle()
                                        .fill(Color(red: 0.35, green: 0.62, blue: 1.0).opacity(0.28))
                                        .padding(1)
                                }
                            }
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 17)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
    }

    /// Weekday component (1…7, Sunday=1) for the given grid column index.
    private func weekdayForGridColumn(_ column: Int) -> Int {
        ((calendar.firstWeekday - 1 + column) % 7) + 1
    }

    private func weekendTint(weekday: Int) -> WeekendTint? {
        switch weekday {
        case 1: return .sunday
        case 7: return .saturday
        default: return nil
        }
    }

    private func dayNumberColor(_ cell: DayGridCell) -> Color {
        if cell.isToday { return Color(red: 0.45, green: 0.78, blue: 1.0) }
        if let w = cell.weekend { return w.color }
        return .white.opacity(0.72)
    }

    private func weekdayHeader(_ column: Int) -> String {
        let syms = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let idx = (column + first) % 7
        return syms[idx]
    }

    private func dayCells() -> [DayGridCell] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var out: [DayGridCell] = []
        var id = 0
        for _ in 0..<lead {
            out.append(DayGridCell(id: id, day: nil, isToday: false, weekend: nil))
            id += 1
        }
        for d in dayRange {
            let date = calendar.date(byAdding: .day, value: d - 1, to: monthStart)!
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let wd = calendar.component(.weekday, from: date)
            let weekend = weekendTint(weekday: wd)
            out.append(DayGridCell(id: id, day: d, isToday: isToday, weekend: weekend))
            id += 1
        }
        while out.count < 42 {
            out.append(DayGridCell(id: id, day: nil, isToday: false, weekend: nil))
            id += 1
        }
        return out
    }
}

private struct DayGridCell {
    let id: Int
    let day: Int?
    let isToday: Bool
    let weekend: WeekendTint?
}

private struct ClockOpenView: View {
    @Bindable var clock: ClockModule
    @State private var mirrorRevealed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            GeometryReader { geo in
                let innerW = geo.size.width
                let innerH = geo.size.height
                let divW = ClockNotchLayout.dividerWidth
                let mirrorW = ClockNotchLayout.mirrorSquare
                let gap = NotchSizing.openClockInterColumnSpacing
                let gapsTotal = gap * 4
                let calW = min(ClockNotchLayout.calendarWidth, max(128, innerW - mirrorW - divW * 2 - gapsTotal - 96))
                let timeW = max(100, innerW - mirrorW - calW - divW * 2 - gapsTotal)

                HStack(alignment: .top, spacing: gap) {
                    ClockSummaryColumn(now: ctx.date)
                        .frame(width: timeW, height: innerH, alignment: .top)

                    NotchClockDivider(maxHeight: innerH)

                    NotchMiniCalendar(now: ctx.date)
                        .frame(width: calW, height: innerH, alignment: .top)

                    NotchClockDivider(maxHeight: innerH)

                    ClockMirrorColumn(clock: clock, mirrorRevealed: $mirrorRevealed)
                        .frame(width: mirrorW, height: innerH, alignment: .center)
                }
                .frame(width: innerW, height: innerH, alignment: .center)
            }
            .padding(.vertical, 10)
            .padding(.bottom, 6)
        }
        .onDisappear {
            mirrorRevealed = false
            clock.mirrorCapture.stop()
        }
    }
}

// MARK: - Mirror column (gated)

private struct ClockMirrorColumn: View {
    @Bindable var clock: ClockModule
    @Binding var mirrorRevealed: Bool

    private var capture: NotchMirrorCapture { clock.mirrorCapture }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            if !mirrorRevealed {
                Button {
                    mirrorRevealed = true
                    capture.startIfNeeded()
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                        Text("Click to show mirror")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .frame(width: ClockNotchLayout.mirrorSquare, height: ClockNotchLayout.mirrorSquare)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                mirrorActiveBody
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var mirrorActiveBody: some View {
        switch capture.phase {
        case .idle, .configuring:
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
                .frame(width: ClockNotchLayout.mirrorSquare, height: ClockNotchLayout.mirrorSquare)
                .frame(maxWidth: .infinity)
        case .unauthorized:
            mirrorNotice(
                "Camera off",
                "Allow camera access in System Settings → Privacy & Security → Camera."
            )
        case .noCamera:
            mirrorNotice("No camera", "This Mac has no video input.")
        case .running:
            if let session = capture.session {
                VStack(spacing: 12) {
                    HStack {
                        Spacer(minLength: 0)
                        NotchMirrorCameraPreview(session: session)
                            .frame(width: ClockNotchLayout.mirrorSquare, height: ClockNotchLayout.mirrorSquare)
                            .scaleEffect(x: -1, y: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Spacer(minLength: 0)
                    }
                    Button {
                        mirrorRevealed = false
                        capture.stop()
                    } label: {
                        Text("Hide mirror")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.vertical, 7)
                            .padding(.horizontal, 16)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                mirrorNotice("Camera", "Starting…")
            }
        case .failed(let msg):
            mirrorNotice("Camera error", msg)
        }
    }

    private func mirrorNotice(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(5)
        }
        .padding(8)
        .frame(width: ClockNotchLayout.mirrorSquare, height: ClockNotchLayout.mirrorSquare)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .frame(maxWidth: .infinity)
    }
}

/// Renders `HH:mm:ss` with a per-digit numeric roll when values change
/// (TimelineView tick every second).
private struct AnimatedClockTime: View {
    let now: Date

    private var calendar: Calendar { .current }

    private var hour: Int { calendar.component(.hour, from: now) }
    private var minute: Int { calendar.component(.minute, from: now) }
    private var second: Int { calendar.component(.second, from: now) }

    private static let digitFont = Font.system(size: 34, weight: .semibold, design: .rounded)
    private static let rollAnimation = Animation.spring(response: 0.38, dampingFraction: 0.78)

    var body: some View {
        HStack(spacing: 0) {
            digitPair(hour)
            colon
            digitPair(minute)
            colon
            digitPair(second)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    private var colon: some View {
        Text(":")
            .font(Self.digitFont)
            .foregroundStyle(.white)
    }

    private func digitPair(_ value: Int) -> some View {
        let v = min(99, max(0, value))
        let tens = v / 10
        let ones = v % 10
        return HStack(spacing: 0) {
            rollingDigit(tens)
            rollingDigit(ones)
        }
    }

    private func rollingDigit(_ digit: Int) -> some View {
        Text(verbatim: String(digit))
            .font(Self.digitFont)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(Self.rollAnimation, value: digit)
    }
}

private struct ClockSummaryColumn: View {
    let now: Date

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: now)
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Text(greeting)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)

            AnimatedClockTime(now: now)

            Text(ClockFormat.fullDate.string(from: now))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
