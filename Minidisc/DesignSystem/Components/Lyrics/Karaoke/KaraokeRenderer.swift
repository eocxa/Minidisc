import SwiftUI

@inline(__always) private func kClamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

private func kSmoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    guard e1 > e0 else { return x < e0 ? 0 : 1 }
    let t = kClamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

/// Draws the karaoke effect one glyph at a time on top of SwiftUI's own text
/// layout, so fonts, kerning, CJK, emoji and line breaks all keep working.
public struct KaraokeRenderer: TextRenderer {
    public var time: TimeInterval
    public var start: TimeInterval
    public var end: TimeInterval
    public var config: KaraokeConfiguration

    public init(
        time: TimeInterval,
        start: TimeInterval,
        end: TimeInterval,
        config: KaraokeConfiguration = .standard
    ) {
        self.time = time
        self.start = start
        self.end = end
        self.config = config
    }

    /// Lets the glow and the bounce draw outside the typographic bounds
    /// without getting clipped.
    public var displayPadding: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    public func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // 1. Collect glyph slices in reading order and accumulate an "unrolled"
        //    width axis, so the sweep advances continuously across line breaks.
        struct Item {
            let slice: Text.Layout.RunSlice
            let rect: CGRect
            let cumX: CGFloat
            let index: Int
        }
        var items: [Item] = []
        var cum: CGFloat = 0
        var idx = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let r = slice.typographicBounds.rect
                    items.append(Item(slice: slice, rect: r, cumX: cum, index: idx))
                    cum += r.width
                    idx += 1
                }
            }
        }
        let totalW = cum
        guard totalW > 0 else { return }

        let feather = config.feather ?? min(totalW * 0.6, 34)
        let duration = max(end - start, 0.001)
        let fill = kClamp01((time - start) / duration)
        // Right edge of the lit region on the unrolled axis; starting at
        // -feather guarantees the first character gets a full transition too.
        let edge = -feather + CGFloat(fill) * (totalW + feather)

        for item in items {
            let r = item.rect
            let centerFrac = Double((item.cumX + r.width * 0.5) / totalW)
            // Moment the sweep passes this character's center.
            let charSung = start + centerFrac * (end - start)

            // Glow envelope: lights up as the character is sung; after the line
            // ends the afterglow fades out left-to-right with a stagger.
            let attack = kSmoothstep(charSung - 0.05, charSung + config.glowAttack, time)
            let releaseAt = end + Double(item.index) * config.releaseStagger
            let release = time <= releaseAt
                ? 1.0
                : exp(-(time - releaseAt) / max(config.glowRelease, 0.01))
            let glow = attack * release * config.glowStrength

            // Bounce envelope: rises when sung; after holding for `bounceHold`
            // each character falls back on its own with a damped oscillation.
            var lift = 0.0
            if config.bounceHeight > 0 || config.bounceScale > 0 {
                let rise = kSmoothstep(charSung - 0.05, charSung + config.bounceRise, time)
                // Per-character fall time: swept + hold; nil = everyone falls at `end`.
                let fallAt = config.bounceHold.map { charSung + $0 } ?? end
                if time <= fallAt {
                    lift = rise
                } else {
                    let dt = time - fallAt
                    lift = rise * exp(-config.settleDamping * dt) * cos(config.settleFrequency * dt)
                }
            }

            // Transform: lift plus a slight scale anchored at the baseline center.
            var base = context
            if lift != 0 {
                base.translateBy(x: 0, y: -config.bounceHeight * CGFloat(lift))
                if config.bounceScale != 0 {
                    let s = 1 + config.bounceScale * CGFloat(lift)
                    base.translateBy(x: r.midX, y: r.maxY)
                    base.scaleBy(x: s, y: s)
                    base.translateBy(x: -r.midX, y: -r.maxY)
                }
            }

            let maskRect = r.insetBy(dx: -2, dy: -2)

            // Dim layer (unsung base color).
            base.drawLayer { (l: inout GraphicsContext) in
                l.draw(item.slice)
                l.blendMode = .sourceIn
                l.fill(Path(maskRect), with: .color(config.dimColor))
            }

            // Lit layer (sweep reveal + glow).
            let localEdge = edge - item.cumX   // lit edge position within this glyph
            guard localEdge + feather > 0 else { continue }

            var litCtx = base
            if glow > 0.02 {
                litCtx.addFilter(.shadow(color: config.glowColor.opacity(0.28 * glow),
                                         radius: config.glowRadius))
                litCtx.addFilter(.shadow(color: config.glowColor.opacity(0.12 * glow),
                                         radius: config.glowRadius * 1.8))
            }
            litCtx.drawLayer { (l: inout GraphicsContext) in
                l.draw(item.slice)
                l.blendMode = .sourceIn
                l.fill(Path(maskRect), with: .color(config.litColor))
                if localEdge < r.width + 2 {
                    // Feathered mask: fully lit left of the edge, fading out
                    // across `feather` points to the right.
                    let w = maskRect.width
                    let solidFrac = kClamp01(Double((localEdge + 2) / w))
                    let fadeFrac = min(max(kClamp01(Double((localEdge + 2 + feather) / w)),
                                           solidFrac + 0.0001), 1.0)
                    l.blendMode = .destinationIn
                    l.fill(Path(maskRect), with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: solidFrac),
                            .init(color: .white.opacity(0), location: fadeFrac),
                            .init(color: .white.opacity(0), location: 1),
                        ]),
                        startPoint: CGPoint(x: maskRect.minX, y: maskRect.midY),
                        endPoint: CGPoint(x: maskRect.maxX, y: maskRect.midY)))
                }
            }
        }
    }
}
