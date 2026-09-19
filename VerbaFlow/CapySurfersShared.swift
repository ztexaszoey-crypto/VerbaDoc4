import SwiftUI
import SpriteKit

// MARK: - MelonIconView
// Custom drawn watermelon slice — green rind, red flesh, black seeds.

struct MelonIconView: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, sz in
            let r  = sz.width / 2
            let cx = r
            let cy = r

            // Green rind (full circle)
            let rind = Path(ellipseIn: CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
            ctx.fill(rind, with: .color(Color(red: 0.15, green: 0.60, blue: 0.22)))

            // Light green stripe
            let stripe = Path(ellipseIn: CGRect(x: sz.width*0.08, y: sz.height*0.08,
                                                width: sz.width*0.84, height: sz.height*0.84))
            ctx.fill(stripe, with: .color(Color(red: 0.25, green: 0.75, blue: 0.32)))

            // Red flesh (inner circle)
            let flesh = Path(ellipseIn: CGRect(x: sz.width*0.18, y: sz.height*0.18,
                                               width: sz.width*0.64, height: sz.height*0.64))
            ctx.fill(flesh, with: .color(Color(red: 0.90, green: 0.22, blue: 0.22)))

            // Seeds — 5 small black ovals
            let seedPositions: [(CGFloat, CGFloat)] = [
                (0,  -0.20), (0.14, 0.06), (-0.14, 0.06), (0.07, -0.10), (-0.07, -0.10)
            ]
            for (dx, dy) in seedPositions {
                let sx = cx + dx * r - 1.5
                let sy = cy + dy * r - 2
                var seed = Path()
                seed.addEllipse(in: CGRect(x: sx, y: sy, width: 3, height: 4.5))
                ctx.fill(seed, with: .color(Color(red: 0.10, green: 0.08, blue: 0.06)))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CoinIconView (watermelon coin for HUD counter)

struct CoinIconView: View {
    var size: CGFloat = 18
    var body: some View {
        Canvas { ctx, sz in
            // Gold circle
            let bg = Path(ellipseIn: CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
            ctx.fill(bg, with: .color(Color(red: 0.96, green: 0.78, blue: 0.18)))
            // Inner ring
            let inner = Path(ellipseIn: CGRect(x: sz.width*0.12, y: sz.height*0.12,
                                               width: sz.width*0.76, height: sz.height*0.76))
            ctx.stroke(inner, with: .color(Color(red: 0.80, green: 0.60, blue: 0.08)), lineWidth: 1.2)
            // "M" letter in center
            var m = Path()
            let lx = sz.width * 0.30
            let rx = sz.width * 0.70
            let top = sz.height * 0.28
            let bot = sz.height * 0.72
            let mid = sz.height * 0.50
            m.move(to: CGPoint(x: lx, y: bot))
            m.addLine(to: CGPoint(x: lx, y: top))
            m.addLine(to: CGPoint(x: sz.width/2, y: mid))
            m.addLine(to: CGPoint(x: rx, y: top))
            m.addLine(to: CGPoint(x: rx, y: bot))
            ctx.stroke(m, with: .color(Color(red: 0.60, green: 0.40, blue: 0.04)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SkinBadgeView
// Draws a unique custom badge for each skin based on its accessory + colors.

struct SkinBadgeView: View {
    let skin: CapySkin
    var size: CGFloat = 48

    private var bodyColor: Color  { Color(red: skin.bodyColor.r,   green: skin.bodyColor.g,   blue: skin.bodyColor.b) }
    private var accentColor: Color { Color(red: skin.accentColor.r, green: skin.accentColor.g, blue: skin.accentColor.b) }

    var body: some View {
        Canvas { ctx, sz in
            let r  = sz.width / 2
            let cx = r; let cy = r

            // Base circle
            let circle = Path(ellipseIn: CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
            ctx.fill(circle, with: .color(bodyColor.opacity(0.25)))
            ctx.stroke(circle, with: .color(accentColor.opacity(0.60)), lineWidth: 2)

            // Accessory-specific inner mark
            drawAccessoryMark(ctx: ctx, sz: sz, cx: cx, cy: cy, r: r)

            // Shine highlight
            let shine = Path(ellipseIn: CGRect(x: sz.width*0.28, y: sz.height*0.14, width: sz.width*0.36, height: sz.height*0.22))
            ctx.fill(shine, with: .color(Color.white.opacity(0.22)))
        }
        .frame(width: size, height: size)
    }

    private func drawAccessoryMark(ctx: GraphicsContext, sz: CGSize, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        let s = r * 0.55   // scale for inner marks

        switch skin.accessory {

        case .none:
            // Simple capy face silhouette — two ear bumps + rounded head
            var head = Path()
            head.addEllipse(in: CGRect(x: cx-s*0.9, y: cy-s*0.65, width: s*1.8, height: s*1.3))
            ctx.fill(head, with: .color(bodyColor.opacity(0.80)))
            for ex in [cx-s*0.5, cx+s*0.3] {
                var ear = Path()
                ear.addEllipse(in: CGRect(x: ex-s*0.25, y: cy-s*1.15, width: s*0.5, height: s*0.6))
                ctx.fill(ear, with: .color(bodyColor.opacity(0.80)))
            }

        case .tie:
            // Red necktie shape
            var top = Path()
            top.move(to: CGPoint(x: cx-s*0.45, y: cy-s*0.80))
            top.addLine(to: CGPoint(x: cx+s*0.45, y: cy-s*0.80))
            top.addLine(to: CGPoint(x: cx+s*0.25, y: cy-s*0.20))
            top.addLine(to: CGPoint(x: cx-s*0.25, y: cy-s*0.20))
            top.closeSubpath()
            ctx.fill(top, with: .color(Color(red:0.80,green:0.12,blue:0.12)))

            var knot = Path()
            knot.addRoundedRect(in: CGRect(x: cx-s*0.22, y: cy-s*0.30, width: s*0.44, height: s*0.22), cornerSize: CGSize(width: 3, height: 3))
            ctx.fill(knot, with: .color(Color(red:0.65,green:0.08,blue:0.08)))

            var blade = Path()
            blade.move(to: CGPoint(x: cx-s*0.22, y: cy-s*0.08))
            blade.addLine(to: CGPoint(x: cx+s*0.22, y: cy-s*0.08))
            blade.addLine(to: CGPoint(x: cx, y: cy+s*0.70))
            blade.closeSubpath()
            ctx.fill(blade, with: .color(Color(red:0.80,green:0.12,blue:0.12)))

        case .scarf:
            // Shuriken / 4-pointed star (ninja)
            for angle in [0.0, Double.pi/4, Double.pi/2, Double.pi*3/4] {
                var point = Path()
                let a = CGFloat(angle)
                let pi = CGFloat.pi
                let tip  = CGPoint(x: cx + cos(a)*s*0.95, y: cy + sin(a)*s*0.95)
                let tipB = CGPoint(x: cx + cos(a + pi)*s*0.95, y: cy + sin(a + pi)*s*0.95)
                let left = CGPoint(x: cx + cos(a + pi/2)*s*0.28, y: cy + sin(a + pi/2)*s*0.28)
                let right = CGPoint(x: cx + cos(a - pi/2)*s*0.28, y: cy + sin(a - pi/2)*s*0.28)
                point.move(to: tip)
                point.addLine(to: left)
                point.addLine(to: tipB)
                point.addLine(to: right)
                point.closeSubpath()
                ctx.fill(point, with: .color(accentColor.opacity(0.90)))
            }

        case .helmet:
            // Rounded helmet with visor bar
            var dome = Path()
            dome.addArc(center: CGPoint(x: cx, y: cy+s*0.10), radius: s*0.85,
                        startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            dome.addLine(to: CGPoint(x: cx+s*0.75, y: cy+s*0.28))
            dome.addLine(to: CGPoint(x: cx-s*0.75, y: cy+s*0.28))
            dome.closeSubpath()
            ctx.fill(dome, with: .color(Color.white.opacity(0.88)))
            // Visor strip
            var visor = Path()
            visor.addRoundedRect(in: CGRect(x: cx-s*0.58, y: cy-s*0.12, width: s*1.16, height: s*0.30),
                                  cornerSize: CGSize(width: 4, height: 4))
            ctx.fill(visor, with: .color(Color(red:0.30,green:0.50,blue:0.90).opacity(0.85)))

        case .eyePatch:
            // Skull & crossbones simplified
            var skull = Path()
            skull.addEllipse(in: CGRect(x: cx-s*0.60, y: cy-s*0.72, width: s*1.20, height: s*0.95))
            ctx.fill(skull, with: .color(Color.white.opacity(0.88)))
            // Eye sockets
            for ex in [cx-s*0.28, cx+s*0.28] {
                var eye = Path(); eye.addEllipse(in: CGRect(x: ex-s*0.16, y: cy-s*0.45, width: s*0.32, height: s*0.30))
                ctx.fill(eye, with: .color(accentColor.opacity(0.9)))
            }
            // Cross bones
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: cx-s*0.50, y: cy+s*0.55))
                p.addLine(to: CGPoint(x: cx+s*0.50, y: cy+s*0.20))
            }, with: .color(Color.white.opacity(0.8)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: cx+s*0.50, y: cy+s*0.55))
                p.addLine(to: CGPoint(x: cx-s*0.50, y: cy+s*0.20))
            }, with: .color(Color.white.opacity(0.8)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

        case .crown:
            // 5-pointed crown
            var crown = Path()
            let baseY = cy + s * 0.50
            let topY  = cy - s * 0.65
            let midY  = cy + s * 0.00
            let points: [CGFloat] = [-s*0.80, -s*0.40, 0, s*0.40, s*0.80]
            let tips:   [CGFloat] = [topY, midY, topY*0.85, midY, topY]
            crown.move(to: CGPoint(x: cx - s*0.80, y: baseY))
            for i in 0..<5 {
                crown.addLine(to: CGPoint(x: cx + points[i], y: tips[i]))
            }
            crown.addLine(to: CGPoint(x: cx + s*0.80, y: baseY))
            crown.closeSubpath()
            ctx.fill(crown, with: .color(Color(red:0.96,green:0.78,blue:0.18)))
            ctx.stroke(crown, with: .color(Color(red:0.80,green:0.58,blue:0.04)), lineWidth: 1.5)
            // Jewels
            for jx in [cx - s*0.38, cx, cx + s*0.38] {
                var gem = Path(); gem.addEllipse(in: CGRect(x: jx-s*0.10, y: baseY-s*0.42, width: s*0.20, height: s*0.20))
                ctx.fill(gem, with: .color(Color(red:0.90,green:0.15,blue:0.15)))
            }

        case .armor:
            // Watermelon slice — green outer + red inner + seeds
            var outer = Path()
            outer.addArc(center: CGPoint(x: cx, y: cy+s*0.20), radius: s*0.88, startAngle: .degrees(210), endAngle: .degrees(330), clockwise: false)
            outer.closeSubpath()
            ctx.fill(outer, with: .color(Color(red:0.15,green:0.60,blue:0.22)))

            var inner = Path()
            inner.addArc(center: CGPoint(x: cx, y: cy+s*0.20), radius: s*0.65, startAngle: .degrees(210), endAngle: .degrees(330), clockwise: false)
            inner.closeSubpath()
            ctx.fill(inner, with: .color(Color(red:0.88,green:0.18,blue:0.18)))

            for (sdx, sdy): (CGFloat, CGFloat) in [(-0.22,0.05),(0,0.05),(0.22,0.05)] {
                var seed = Path(); seed.addEllipse(in: CGRect(x: cx+sdx*s-2, y: cy+sdy*s+s*0.10, width: 4, height: 6))
                ctx.fill(seed, with: .color(Color(red:0.08,green:0.06,blue:0.04)))
            }
        }
    }
}

// MARK: - PowerupIconView (SwiftUI)

struct PowerupIconView: View {
    let type: PowerupType
    var size: CGFloat = 22
    var color: Color

    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width / 2; let cy = sz.height / 2
            let s  = sz.width * 0.44

            switch type {

            case .magnet:
                // U-shape magnet
                var arc = Path(); arc.addArc(center: CGPoint(x:cx,y:cy-s*0.60+s*1.2/2), radius: s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                ctx.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                // Arms
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: cx-s, y: cy-s*0.60+s*0.60))
                    p.addLine(to: CGPoint(x: cx-s, y: cy+s*0.55))
                }, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: cx+s, y: cy-s*0.60+s*0.60))
                    p.addLine(to: CGPoint(x: cx+s, y: cy+s*0.55))
                }, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                // Poles
                var lPole = Path(); lPole.addRoundedRect(in: CGRect(x: cx-s-3, y: cy+s*0.44, width: 7, height: s*0.32), cornerSize: CGSize(width:2,height:2))
                ctx.fill(lPole, with: .color(Color(red:0.90,green:0.20,blue:0.20)))
                var rPole = Path(); rPole.addRoundedRect(in: CGRect(x: cx+s-3, y: cy+s*0.44, width: 7, height: s*0.32), cornerSize: CGSize(width:2,height:2))
                ctx.fill(rPole, with: .color(Color(red:0.20,green:0.40,blue:1.0)))

            case .shield:
                // Pentagon shield
                var shield = Path()
                shield.move(to: CGPoint(x: cx, y: cy-s))
                shield.addLine(to: CGPoint(x: cx+s*0.85, y: cy-s*0.30))
                shield.addLine(to: CGPoint(x: cx+s*0.85, y: cy+s*0.30))
                shield.addCurve(to: CGPoint(x: cx, y: cy+s),
                                control1: CGPoint(x: cx+s*0.85, y: cy+s*0.75),
                                control2: CGPoint(x: cx+s*0.42, y: cy+s))
                shield.addCurve(to: CGPoint(x: cx-s*0.85, y: cy+s*0.30),
                                control1: CGPoint(x: cx-s*0.42, y: cy+s),
                                control2: CGPoint(x: cx-s*0.85, y: cy+s*0.75))
                shield.addLine(to: CGPoint(x: cx-s*0.85, y: cy-s*0.30))
                shield.closeSubpath()
                ctx.fill(shield, with: .color(color.opacity(0.28)))
                ctx.stroke(shield, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                // Inner cross
                ctx.stroke(Path { p in p.move(to: CGPoint(x:cx,y:cy-s*0.42)); p.addLine(to: CGPoint(x:cx,y:cy+s*0.42)) },
                           with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ctx.stroke(Path { p in p.move(to: CGPoint(x:cx-s*0.35,y:cy)); p.addLine(to: CGPoint(x:cx+s*0.35,y:cy)) },
                           with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            case .rocket:
                // Rocket body + nose + fins + flame
                var body = Path(); body.addRoundedRect(in: CGRect(x:cx-s*0.32,y:cy-s*0.50,width:s*0.64,height:s*1.10), cornerSize: CGSize(width:s*0.18,height:s*0.18))
                ctx.fill(body, with: .color(color))
                // Nose cone
                var nose = Path()
                nose.move(to: CGPoint(x:cx, y:cy-s))
                nose.addLine(to: CGPoint(x:cx-s*0.32, y:cy-s*0.50))
                nose.addLine(to: CGPoint(x:cx+s*0.32, y:cy-s*0.50))
                nose.closeSubpath()
                ctx.fill(nose, with: .color(color))
                // Fins
                for xm: CGFloat in [-1,1] {
                    var fin = Path()
                    fin.move(to: CGPoint(x:cx+xm*s*0.32, y:cy+s*0.20))
                    fin.addLine(to: CGPoint(x:cx+xm*s*0.76, y:cy+s*0.65))
                    fin.addLine(to: CGPoint(x:cx+xm*s*0.32, y:cy+s*0.60))
                    fin.closeSubpath()
                    ctx.fill(fin, with: .color(color.opacity(0.8)))
                }
                // Flame
                var flame = Path(); flame.addEllipse(in: CGRect(x:cx-s*0.22,y:cy+s*0.55,width:s*0.44,height:s*0.55))
                ctx.fill(flame, with: .color(Color(red:1.0,green:0.55,blue:0.10).opacity(0.9)))
                var flameInner = Path(); flameInner.addEllipse(in: CGRect(x:cx-s*0.12,y:cy+s*0.68,width:s*0.24,height:s*0.30))
                ctx.fill(flameInner, with: .color(Color.white.opacity(0.7)))

            case .turbo:
                // Lightning bolt
                var bolt = Path()
                bolt.move(to: CGPoint(x:cx+s*0.28, y:cy-s*1.0))
                bolt.addLine(to: CGPoint(x:cx-s*0.14, y:cy-s*0.08))
                bolt.addLine(to: CGPoint(x:cx+s*0.20, y:cy-s*0.08))
                bolt.addLine(to: CGPoint(x:cx-s*0.28, y:cy+s*1.0))
                bolt.addLine(to: CGPoint(x:cx+s*0.14, y:cy+s*0.08))
                bolt.addLine(to: CGPoint(x:cx-s*0.20, y:cy+s*0.08))
                bolt.closeSubpath()
                ctx.fill(bolt, with: .color(color))

            case .headStart, .doubleCoins, .timeFreeze, .brainBoost:
                // Fallback: simple filled circle in the given tint,
                // for powerup types without a bespoke drawn icon yet.
                let dot = Path(ellipseIn: CGRect(x: cx-s*0.5, y: cy-s*0.5, width: s, height: s))
                ctx.fill(dot, with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - TrophyIconView

struct TrophyIconView: View {
    var size: CGFloat = 16
    var color: Color = Color(red: 0.96, green: 0.78, blue: 0.18)

    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width/2; let cy = sz.height/2; let s = sz.width * 0.45
            // Cup
            var cup = Path()
            cup.addArc(center: CGPoint(x:cx,y:cy-s*0.20), radius: s*0.85, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            cup.addLine(to: CGPoint(x:cx+s*0.75, y:cy+s*0.30))
            cup.addLine(to: CGPoint(x:cx-s*0.75, y:cy+s*0.30))
            cup.closeSubpath()
            ctx.fill(cup, with: .color(color))
            // Stem
            ctx.fill(Path(CGRect(x:cx-s*0.18,y:cy+s*0.28,width:s*0.36,height:s*0.45)), with: .color(color))
            // Base
            var base = Path(); base.addRoundedRect(in: CGRect(x:cx-s*0.55,y:cy+s*0.68,width:s*1.10,height:s*0.28), cornerSize: CGSize(width:3,height:3))
            ctx.fill(base, with: .color(color))
            // Handles
            for xm: CGFloat in [-1,1] {
                ctx.stroke(Path { p in
                    p.addArc(center: CGPoint(x:cx+xm*s*0.82,y:cy-s*0.08), radius: s*0.26, startAngle: .degrees(270), endAngle: .degrees(90), clockwise: xm > 0)
                }, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - ShopCartIconView

struct ShopCartIconView: View {
    var size: CGFloat = 18
    var color: Color = .white

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width * 0.44; let cx = sz.width/2; let cy = sz.height/2

            // Handle bar
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x:cx-s*0.95,y:cy-s*0.62))
                p.addLine(to: CGPoint(x:cx-s*0.60,y:cy-s*0.62))
            }, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Cart body trapezoid
            var cart = Path()
            cart.move(to: CGPoint(x:cx-s*0.60,y:cy-s*0.62))
            cart.addLine(to: CGPoint(x:cx+s*0.75,y:cy-s*0.62))
            cart.addLine(to: CGPoint(x:cx+s*0.95,y:cy+s*0.40))
            cart.addLine(to: CGPoint(x:cx-s*0.35,y:cy+s*0.40))
            cart.closeSubpath()
            ctx.fill(cart, with: .color(color.opacity(0.22)))
            ctx.stroke(cart, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))

            // Wheels
            for wx in [cx-s*0.10, cx+s*0.65] {
                ctx.stroke(Path(ellipseIn: CGRect(x:wx-s*0.18,y:cy+s*0.44,width:s*0.36,height:s*0.36)),
                           with: .color(color), lineWidth: 2.2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - WaveIconView (for entry screen wave decoration)
//
// Phase 6: default color is now `VerbaTheme.cozyLime` (vibrant lime)
// to bake the matcha palette into the source. The original bright
// cyan default clashed with the warm green aesthetic and was the
// reason the directive explicitly called for "removing the blue wave
// icons" on the Capy Surfers entry screen. Callers can still pass an
// explicit `color:` to override when a different surface demands it.

struct WaveIconView: View {
    var size: CGFloat = 32
    var color: Color = VerbaTheme.cozyLime

    var body: some View {
        Canvas { ctx, sz in
            let cy = sz.height * 0.50
            let w  = sz.width
            // Three wave arcs stacked
            for (yOff, alpha): (CGFloat, CGFloat) in [(0,1.0),(-sz.height*0.20,0.55),(-sz.height*0.38,0.28)] {
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: cy+yOff))
                wave.addCurve(to: CGPoint(x: w*0.50, y: cy+yOff),
                              control1: CGPoint(x: w*0.12, y: cy+yOff-sz.height*0.25),
                              control2: CGPoint(x: w*0.38, y: cy+yOff+sz.height*0.25))
                wave.addCurve(to: CGPoint(x: w, y: cy+yOff),
                              control1: CGPoint(x: w*0.62, y: cy+yOff-sz.height*0.25),
                              control2: CGPoint(x: w*0.88, y: cy+yOff+sz.height*0.25))
                ctx.stroke(wave, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}
