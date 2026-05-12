import AppKit
import Observation
import SwiftUI

/// Default fallback module — used as the open-pill content when nothing else
/// (Tray, Music) is active. **Reports `isActive == false`** so it does not
/// surface itself in the closed pill: by default the closed state stays as
/// the bare physical notch and the user reveals the clock by hovering.
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

    var openView: AnyView { AnyView(ClockOpenView()) }
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

    /// Month-name header for the calendar grid.
    static let monthName: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("LLLL")
        return f
    }()

    static let year: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
}

// MARK: - Open view

private struct ClockOpenView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(alignment: .center, spacing: 22) {
                ClockSummaryColumn(now: ctx.date)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                MonthCalendarView(now: ctx.date)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            AnimatedClockTime(now: now)

            Text(ClockFormat.fullDate.string(from: now))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 180, alignment: .leading)
    }
}

// MARK: - Month grid

private struct MonthCalendarView: View {
    let now: Date

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        let comps = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: comps) ?? now
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: now)?.count ?? 30
    }

    /// Empty cells before day 1, honoring the locale's `firstWeekday`.
    private var leadingBlanks: Int {
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        return (firstWeekday - calendar.firstWeekday + 7) % 7
    }

    private var today: Int { calendar.component(.day, from: now) }

    private var weekdaySymbols: [String] {
        let base = calendar.veryShortStandaloneWeekdaySymbols      // Sun…Sat
        let i = calendar.firstWeekday - 1
        return Array(base[i...] + base[..<i])
    }

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 14), spacing: 2),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Month + year header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ClockFormat.monthName.string(from: now))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                Text(ClockFormat.year.string(from: now))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            // Weekday strip
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(height: 12)
                }
            }

            // Day grid — 18pt cells with 2pt spacing comfortably fits 6 rows.
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 18)
                }
                ForEach(1...daysInMonth, id: \.self) { day in
                    dayCell(day: day, isToday: day == today)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dayCell(day: Int, isToday: Bool) -> some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
            }
            Text("\(day)")
                .font(.system(
                    size: 11,
                    weight: isToday ? .bold : .medium,
                    design: .rounded
                ))
                .foregroundStyle(isToday ? Color.black : .white.opacity(0.85))
                .monospacedDigit()
        }
        .frame(height: 18)
    }
}
