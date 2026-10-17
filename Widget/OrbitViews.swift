import QuotaCore
import SwiftUI
import WidgetKit

/// 5h ring with the remaining percentage inside; the fill is the share of quota left.
struct OrbitRing: View {
    let tile: ProviderTile
    let size: CGFloat
    let numberSize: CGFloat

    var body: some View {
        let stroke = size * 0.08
        let diameter = size * 0.9
        ZStack {
            if let icon = tile.emptyIcon {
                Circle().stroke(OrbitTheme.track, style: StrokeStyle(lineWidth: stroke * 0.75, lineCap: .round, dash: [0.01, stroke * 1.6]))
                    .frame(width: diameter, height: diameter)
                StateIcon(kind: icon, size: size * 0.34, color: OrbitTheme.muted)
            } else {
            Circle().stroke(OrbitTheme.track, lineWidth: stroke).frame(width: diameter, height: diameter)
            if RingGauge.fraction(tile.fiveHour) > 0 {
                Circle().trim(from: 0, to: RingGauge.fraction(tile.fiveHour))
                    .stroke(OrbitTheme.fill(tile.fiveHour), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: diameter, height: diameter)
            }
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(PercentText.text(tile.fiveHour)).font(.system(size: numberSize, weight: .medium)).monospacedDigit()
                    if tile.fiveHour != nil { Text("%").font(.system(size: numberSize * 0.4)) }
                }
                FiveHourCaption(tile: tile, size: max(numberSize * 0.36, 7))
            }.foregroundStyle(OrbitTheme.text)
            }
        }
        .frame(width: size, height: size)
        .opacity(tile.isStale ? OrbitTheme.dimmed : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) 5-hour: " + (tile.fiveHour.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
    }
}

/// Only the empty state is spelled out; freshness shows as a small grey clock beside the provider name.
struct OrbitFooter: View {
    let entry: QuotaEntry
    var body: some View {
        if entry.snapshot == nil {
            Text("No data · open app to refresh").font(.system(size: 9)).foregroundStyle(OrbitTheme.muted).lineLimit(1)
        }
    }
}

/// The 5h caption under the percentage: time left in that window ("2h 14m*"), redrawn every minute.
struct FiveHourCaption: View {
    let tile: ProviderTile
    let size: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let left = ResetCountdown.remaining(until: tile.fiveHourReset, now: context.date) ?? "—"
            Text(left + (tile.fiveHourIsLow ? "*" : ""))
        }
        .font(.system(size: size)).foregroundStyle(OrbitTheme.muted)
    }
}

/// Top-half arc from the left end over the top to the right end.
struct HalfArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width / 2,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        return path
    }
}

/// Small tile's 5h gauge: a semicircle with the remaining percentage inside the arc.
/// Everything is laid out on one centre line and the whole gauge shrinks to the width it is given.
struct OrbitHalfGauge: View {
    let tile: ProviderTile
    private static let design = CGSize(width: 124, height: 70)
    private let radius: CGFloat = 48.7
    private let line: CGFloat = 9.3

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1.06, proxy.size.width / Self.design.width)
            gauge
                .frame(width: Self.design.width, height: Self.design.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: Self.design.height)
        .opacity(tile.isStale ? OrbitTheme.dimmed : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) 5-hour: " + (tile.fiveHour.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
    }

    private var gauge: some View {
        let fraction = RingGauge.fraction(tile.fiveHour)
        return ZStack(alignment: .bottom) {
            if let icon = tile.emptyIcon {
                HalfArc().stroke(OrbitTheme.track, style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round, dash: [0.01, 11]))
                    .frame(width: radius * 2, height: radius).padding(.bottom, 10)
                StateIcon(kind: icon, size: 30, color: OrbitTheme.muted).padding(.bottom, 6)
            } else {
            HalfArc().stroke(OrbitTheme.track, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .frame(width: radius * 2, height: radius).padding(.bottom, 10)
            if fraction > 0 {
                HalfArc().trim(from: 0, to: fraction)
                    .stroke(OrbitTheme.fill(tile.fiveHour), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: radius * 2, height: radius).padding(.bottom, 10)
            }
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(PercentText.text(tile.fiveHour)).font(.system(size: 30, weight: .medium)).monospacedDigit()
                    if tile.fiveHour != nil { Text("%").font(.system(size: 11)) }
                }
                FiveHourCaption(tile: tile, size: 9)
            }
            .foregroundStyle(OrbitTheme.text)
            .padding(.bottom, -7)
            }
        }
    }
}

/// W1: ten thin segments; each lights up for a tenth of the remaining weekly quota.
struct OrbitSegmentBar: View {
    let percent: Double?
    var height: CGFloat = 5
    var gap: CGFloat = 2

    var body: some View {
        let filled = SegmentBar.filled(percent, count: 10)
        HStack(spacing: gap) {
            ForEach(0..<10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < filled ? OrbitTheme.fill(percent) : OrbitTheme.track)
                    .frame(height: height)
            }
        }
    }
}

/// W1 weekly reading shared by every size: "7d 33%" over ten segments, then the reset countdown.
struct OrbitWeeklyBar: View {
    struct Metrics {
        let text: CGFloat
        let spacing: CGFloat
        let barHeight: CGFloat
        let segmentGap: CGFloat
    }

    let tile: ProviderTile
    let entry: QuotaEntry
    let metrics: Metrics

    var body: some View {
        let reset = ResetCountdown.text(until: tile.weeklyReset, now: entry.date)
        VStack(spacing: metrics.spacing) {
            HStack {
                Text("7d" + (tile.weeklyIsLow ? "*" : "")).foregroundStyle(OrbitTheme.muted)
                Spacer(minLength: 0)
                Text(tile.weekly.map { "\(PercentText.text($0))%" } ?? "—").fontWeight(.semibold)
                    .foregroundStyle(OrbitTheme.weekly)
            }.font(.system(size: metrics.text)).monospacedDigit()
            OrbitSegmentBar(percent: tile.weekly,
                            height: metrics.barHeight, gap: metrics.segmentGap)
            Group {
                if tile.availability == .authorizationNeeded {
                    Text("Authorize").foregroundStyle(OrbitTheme.text)
                } else if let reset {
                    Text("↻ " + reset)
                } else {
                    Text(" ")
                }
            }.font(.system(size: metrics.text - 1)).foregroundStyle(OrbitTheme.muted).lineLimit(1)
        }
        .opacity(tile.isStale ? OrbitTheme.dimmed : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) weekly: "
            + (tile.weekly.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
    }
}

struct OrbitSmallView: View {
    let entry: QuotaEntry

    var body: some View {
        let tiles = entry.tiles
        let tile = tiles[ProviderCycle.clamped(entry.providerIndex, count: tiles.count)]
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if entry.snapshot == nil {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 13)).foregroundStyle(OrbitTheme.gauge)
                        .frame(width: 17, height: 17)
                    Text("Arcmeter").font(.system(size: 10, weight: .semibold))
                    Spacer(minLength: 0)
                } else {
                    ProviderLogo(mark: tile.mark, size: 17)
                    Text(tile.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    StaleMark(tile: tile, size: 9)
                    Spacer(minLength: 0)
                    Button(intent: NextProviderIntent()) {
                        Text("›").font(.system(size: 25)).foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 28, height: 28, alignment: .trailing).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Next provider")
                }
            }.frame(height: 20).offset(y: -5)
            Spacer(minLength: 0)
            OrbitHalfGauge(tile: tile)
            Spacer(minLength: 0)
            if tile.availability == .measured {
                OrbitWeeklyBar(tile: tile, entry: entry, metrics: .init(text: 10, spacing: 5, barHeight: 5, segmentGap: 2))
            } else {
                stateNote(tile)
            }
        }
        .padding(15).foregroundStyle(OrbitTheme.text)
    }
}

extension OrbitSmallView {
    /// Two short lines under the illustration; nothing measured, so no percentages are drawn.
    fileprivate func stateNote(_ tile: ProviderTile) -> some View {
        let authorize = tile.availability == .authorizationNeeded
        return VStack(spacing: 2) {
            Text(authorize ? "Authorization needed" : (entry.snapshot == nil ? "No data" : "No reading"))
                .fontWeight(.semibold).foregroundStyle(OrbitTheme.text)
            Text(authorize ? "Open app to authorize" : "Open app to refresh").foregroundStyle(OrbitTheme.muted)
        }.font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7).multilineTextAlignment(.center).frame(height: 31)
    }
}

/// Pads a layout by the system content margins, never less than 12 pt, so it stays inside the widget's real content area.
struct ContentMargins: ViewModifier {
    @Environment(\.widgetContentMargins) private var margins

    func body(content: Content) -> some View {
        content
            .padding(.leading, max(margins.leading, 12)).padding(.trailing, max(margins.trailing, 12))
            .padding(.top, max(margins.top, 12)).padding(.bottom, max(margins.bottom, 12))
    }
}

/// Fits its content to the space it is offered: shrinks when short of room and grows by at most `maxScale`.
struct FitToSpace<Content: View>: View {
    let design: CGSize
    var maxScale: CGFloat = 1
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            let scale = min(maxScale, proxy.size.width / design.width, proxy.size.height / design.height)
            content
                .frame(width: design.width, height: design.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// The medium ring row: Claude, Codex, and agy Gemini (no agy Claude/GPT), fitted to the content margins.
struct OrbitRowView: View {
    struct Layout {
        let tileWidth: CGFloat
        let spacing: CGFloat
        let gap: CGFloat
        let ring: CGFloat
        let number: CGFloat
        let logo: CGFloat
        let name: CGFloat
        let barWidth: CGFloat
        let weekly: OrbitWeeklyBar.Metrics
        let height: CGFloat
        let maxScale: CGFloat

        func design(count: Int) -> CGSize {
            CGSize(width: tileWidth * CGFloat(count) + spacing * CGFloat(max(count - 1, 0)), height: height)
        }

        static let medium = Layout(tileWidth: 112, spacing: 10, gap: 1, ring: 96, number: 24,
                                   logo: 15, name: 10.5, barWidth: 104,
                                   weekly: .init(text: 12, spacing: 2, barHeight: 5.5, segmentGap: 1.5), height: 153, maxScale: 1.2)
    }

    let entry: QuotaEntry
    let layout: Layout

    var body: some View {
        let tiles = ProviderTile.withoutAgyClaudeGPT(entry.tiles)
        FitToSpace(design: layout.design(count: tiles.count), maxScale: layout.maxScale) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: layout.spacing) {
                    ForEach(tiles) { tile in
                        VStack(spacing: 0) {
                            HStack(spacing: 3) {
                                ProviderLogo(mark: tile.mark, size: layout.logo)
                                Text(tile.name).font(.system(size: layout.name, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                StaleMark(tile: tile, size: layout.name - 1)
                            }.padding(.bottom, 5)
                            Spacer(minLength: layout.gap)
                            OrbitRing(tile: tile, size: layout.ring, numberSize: layout.number)
                            Spacer(minLength: layout.gap)
                            OrbitWeeklyBar(tile: tile, entry: entry, metrics: layout.weekly)
                                .frame(width: layout.barWidth)
                        }.frame(width: layout.tileWidth)
                    }
                }
                OrbitFooter(entry: entry).padding(.top, 4)
            }
        }
        .modifier(ContentMargins())
        .foregroundStyle(OrbitTheme.text)
    }
}

struct OrbitMediumView: View {
    let entry: QuotaEntry
    var body: some View { OrbitRowView(entry: entry, layout: .medium) }
}

/// The 2x2 grid is designed at its natural size and fitted to the content margins, so the four rings, percentages
/// and weekly segments are as large as the widget allows and nothing is clipped.
struct OrbitLargeView: View {
    private static let design = CGSize(width: 300, height: 356)
    let entry: QuotaEntry

    var body: some View {
        FitToSpace(design: Self.design, maxScale: 1.15) {
            VStack(spacing: 0) {
                Grid(horizontalSpacing: 20, verticalSpacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(entry.tiles.dropFirst(row * 2).prefix(2)) { tile in
                                VStack(spacing: 7) {
                                    HStack(spacing: 6) {
                                        ProviderLogo(mark: tile.mark, size: 18)
                                        Text(tile.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                        StaleMark(tile: tile, size: 10)
                                    }.padding(.bottom, 5)
                                    OrbitRing(tile: tile, size: 96, numberSize: 30)
                                    OrbitWeeklyBar(tile: tile, entry: entry,
                                                   metrics: .init(text: 12, spacing: 4, barHeight: 6, segmentGap: 2))
                                        .frame(width: 136)
                                }.frame(width: 140)
                            }
                        }
                    }
                }
                OrbitFooter(entry: entry).padding(.top, 4)
            }
        }
        .modifier(ContentMargins())
        .foregroundStyle(OrbitTheme.text)
    }
}
