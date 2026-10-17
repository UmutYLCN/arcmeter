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
                Text("5h" + (tile.fiveHourIsLow ? "*" : "")).font(.system(size: max(numberSize * 0.36, 7)))
                    .foregroundStyle(OrbitTheme.muted)
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
struct OrbitHalfGauge: View {
    let tile: ProviderTile
    private let radius: CGFloat = 48.7
    private let line: CGFloat = 9.3

    var body: some View {
        let fraction = RingGauge.fraction(tile.fiveHour)
        ZStack(alignment: .bottom) {
            if let icon = tile.emptyIcon {
                HalfArc().stroke(OrbitTheme.track, style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round, dash: [0.01, 11]))
                    .frame(width: radius * 2, height: radius).position(x: 58, y: 60 - radius / 2)
                StateIcon(kind: icon, size: 30, color: OrbitTheme.muted).padding(.bottom, 6)
            } else {
            HalfArc().stroke(OrbitTheme.track, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .frame(width: radius * 2, height: radius).position(x: 58, y: 60 - radius / 2)
            if fraction > 0 {
                HalfArc().trim(from: 0, to: fraction)
                    .stroke(OrbitTheme.fill(tile.fiveHour), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: radius * 2, height: radius).position(x: 58, y: 60 - radius / 2)
            }
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(PercentText.text(tile.fiveHour)).font(.system(size: 30, weight: .medium)).monospacedDigit()
                    if tile.fiveHour != nil { Text("%").font(.system(size: 11)) }
                }
                Text("5h" + (tile.fiveHourIsLow ? "*" : "")).font(.system(size: 9)).foregroundStyle(OrbitTheme.muted)
            }
            .foregroundStyle(OrbitTheme.text)
            .padding(.bottom, -7)
            }
        }
        .scaleEffect(1.06)
        .frame(width: 124, height: 70)
        .opacity(tile.isStale ? OrbitTheme.dimmed : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) 5-hour: " + (tile.fiveHour.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
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
            }.frame(height: 20)
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
        }.font(.system(size: 10)).multilineTextAlignment(.center).frame(height: 31)
    }
}

struct OrbitMediumView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(entry.tiles) { tile in
                    VStack(spacing: 0) {
                        HStack(spacing: 3) {
                            ProviderLogo(mark: tile.mark, size: 14)
                            Text(tile.name).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            StaleMark(tile: tile, size: 8)
                        }
                        Spacer(minLength: 2)
                        OrbitRing(tile: tile, size: 82, numberSize: 20)
                        Spacer(minLength: 2)
                        OrbitWeeklyBar(tile: tile, entry: entry,
                                       metrics: .init(text: 11, spacing: 3, barHeight: 5, segmentGap: 1.5))
                    }.frame(maxWidth: .infinity)
                }
            }
            OrbitFooter(entry: entry).padding(.top, 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 10).foregroundStyle(OrbitTheme.text)
    }
}

struct OrbitLargeView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 20, verticalSpacing: 10) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(entry.tiles.dropFirst(row * 2).prefix(2)) { tile in
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    ProviderLogo(mark: tile.mark, size: 18)
                                    Text(tile.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    StaleMark(tile: tile, size: 10)
                                }
                                OrbitRing(tile: tile, size: 96, numberSize: 29)
                                OrbitWeeklyBar(tile: tile, entry: entry,
                                               metrics: .init(text: 11, spacing: 4, barHeight: 6, segmentGap: 2))
                                    .frame(width: 136)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            OrbitFooter(entry: entry).padding(.top, 4)
        }
        .padding(.horizontal, 20).padding(.vertical, 18).foregroundStyle(OrbitTheme.text)
    }
}
