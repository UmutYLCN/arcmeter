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
        let diameter = size * 0.84
        ZStack {
            if let icon = tile.emptyIcon {
                Circle().stroke(OrbitTheme.track, style: StrokeStyle(lineWidth: stroke * 0.75, lineCap: .round, dash: [0.01, stroke * 1.6]))
                    .frame(width: diameter, height: diameter)
                StateIcon(kind: icon, size: size * 0.34, color: icon == .lock ? OrbitTheme.stale : OrbitTheme.muted)
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
        .opacity(tile.isStale ? 0.6 : 1)
        .overlay(alignment: .topTrailing) {
            if tile.isStale && tile.availability == .measured { StaleBadge(size: size * 0.3).offset(x: size * 0.04, y: -size * 0.02) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name) 5-hour: " + (tile.fiveHour.map { "\(Int($0.rounded())) percent remaining" } ?? "no data"))
    }
}

/// Only the empty state is spelled out; freshness shows as the per-provider clock badge.
struct OrbitFooter: View {
    let entry: QuotaEntry
    var body: some View {
        Text(entry.snapshot == nil ? "No data · open app to refresh" : " ")
            .font(.system(size: 8)).foregroundStyle(OrbitTheme.muted).lineLimit(1)
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
                StateIcon(kind: icon, size: 30, color: icon == .lock ? OrbitTheme.stale : OrbitTheme.muted).padding(.bottom, 6)
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
        .frame(width: 116, height: 66)
        .opacity(tile.isStale ? 0.6 : 1)
        .overlay(alignment: .topTrailing) {
            if tile.isStale && tile.availability == .measured { StaleBadge(size: 26).offset(x: 6, y: -4) }
        }
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
                    Text("Authorize").foregroundStyle(OrbitTheme.stale)
                } else if let reset {
                    Text("↻ " + reset)
                } else {
                    Text(" ")
                }
            }.font(.system(size: metrics.text - 1)).foregroundStyle(OrbitTheme.muted).lineLimit(1)
        }
        .opacity(tile.isStale ? 0.6 : 1)
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
                    Spacer(minLength: 0)
                    Button(intent: NextProviderIntent()) {
                        Text("›").font(.system(size: 25)).foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 28, height: 28).contentShape(Rectangle())
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
                .fontWeight(.semibold).foregroundStyle(authorize ? OrbitTheme.stale : OrbitTheme.text)
            Text(authorize ? "Open app to authorize" : "Open app to refresh").foregroundStyle(OrbitTheme.muted)
        }.font(.system(size: 10)).multilineTextAlignment(.center).frame(height: 31)
    }
}

struct OrbitMediumView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(entry.tiles) { tile in
                    VStack(spacing: 3) {
                        VStack(spacing: 2) {
                            ProviderLogo(mark: tile.mark, size: 13)
                            Text(tile.name).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        OrbitRing(tile: tile, size: 58, numberSize: 13.5)
                        OrbitWeeklyBar(tile: tile, entry: entry,
                                       metrics: .init(text: 8, spacing: 2, barHeight: 4, segmentGap: 1))
                    }.frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            OrbitFooter(entry: entry).frame(maxWidth: .infinity, alignment: .trailing).frame(height: 10)
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8).foregroundStyle(OrbitTheme.text)
    }
}

struct OrbitLargeView: View {
    let entry: QuotaEntry

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Grid(horizontalSpacing: 28, verticalSpacing: 14) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(entry.tiles.dropFirst(row * 2).prefix(2)) { tile in
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    ProviderLogo(mark: tile.mark, size: 17)
                                    Text(tile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                OrbitRing(tile: tile, size: 84, numberSize: 25)
                                OrbitWeeklyBar(tile: tile, entry: entry,
                                               metrics: .init(text: 10, spacing: 4, barHeight: 5, segmentGap: 2))
                                    .frame(width: 116)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
            }.padding(.bottom, 12)
            OrbitFooter(entry: entry)
        }
        .padding(24).foregroundStyle(OrbitTheme.text)
    }
}
