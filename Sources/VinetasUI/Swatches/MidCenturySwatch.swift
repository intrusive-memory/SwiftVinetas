// MidCenturySwatch.swift
// VinetasUI
//
// The 56 × 40 swatch for the Mid-Century Modern style row: a sun with rays,
// two atomic stars and a strolling silhouette over a hill, after the
// Bewitched / Pink Panther opening credits.

import SwiftUI

/// A self-contained `Canvas` that renders a static Mid-Century scene.
///
/// Designed for a 56 × 40 frame; it draws into an internal 56 × 40 view box
/// so the shapes scale with the frame. It is drawn once, at `t: 0`. The
/// Vinetas handoff specified a looping animation, but a continuous redraw at
/// display refresh competes with MLX / Metal generation for the same GPU and
/// can starve a generation's completion, so the scene stays still.
struct MidCenturySwatch: View {

  // Scene view box (matches the SVG handoff).
  private let vbW: CGFloat = 56
  private let vbH: CGFloat = 40

  var body: some View {
    Canvas { ctx, size in
      let sx = size.width / vbW
      let sy = size.height / vbH
      let s = min(sx, sy)
      let offsetX = (size.width - vbW * s) / 2
      let offsetY = (size.height - vbH * s) / 2

      ctx.translateBy(x: offsetX, y: offsetY)
      ctx.scaleBy(x: s, y: s)

      drawSky(in: &ctx)
      drawLand(in: &ctx)
      drawHill(in: &ctx)
      drawSun(in: &ctx, t: 0)
      drawRays(in: &ctx, t: 0)
      drawAtomicStar(in: &ctx, center: CGPoint(x: 46, y: 9), scale: 1.0, period: 7.0, t: 0)
      drawAtomicStar(in: &ctx, center: CGPoint(x: 30, y: 7), scale: 0.65, period: -9.0, t: 0)
      drawSilhouette(in: &ctx, t: 0)
    }
  }

  // MARK: - Layers

  private func drawSky(in ctx: inout GraphicsContext) {
    let sky = Path(CGRect(x: 0, y: 0, width: vbW, height: vbH))
    ctx.fill(sky, with: .color(Color(red: 0xf0 / 255, green: 0xd8 / 255, blue: 0xa3 / 255)))
  }

  private func drawLand(in ctx: inout GraphicsContext) {
    let land = Path(CGRect(x: 0, y: 26, width: vbW, height: vbH - 26))
    ctx.fill(land, with: .color(Color(red: 0x1f / 255, green: 0x6a / 255, blue: 0x64 / 255)))
  }

  private func drawHill(in ctx: inout GraphicsContext) {
    var p = Path()
    p.move(to: CGPoint(x: -4, y: 32))
    p.addQuadCurve(to: CGPoint(x: vbW + 4, y: 30), control: CGPoint(x: vbW / 2, y: 18))
    p.addLine(to: CGPoint(x: vbW + 4, y: vbH))
    p.addLine(to: CGPoint(x: -4, y: vbH))
    p.closeSubpath()
    ctx.fill(
      p,
      with: .color(Color(red: 0xc4 / 255, green: 0x92 / 255, blue: 0x3a / 255).opacity(0.85)))
  }

  private func drawSun(in ctx: inout GraphicsContext, t: TimeInterval) {
    let phase = (t.truncatingRemainder(dividingBy: 3.2)) / 3.2
    let pulse = 0.5 - 0.5 * cos(phase * 2 * .pi)  // 0 → 1 → 0
    let r = 5.6 + pulse * 1.0
    let center = CGPoint(x: 11, y: 13)
    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    ctx.fill(
      Path(ellipseIn: rect),
      with: .color(Color(red: 0xc5 / 255, green: 0x48 / 255, blue: 0x2a / 255)))
  }

  private func drawRays(in ctx: inout GraphicsContext, t: TimeInterval) {
    let center = CGPoint(x: 11, y: 13)
    let phase = (t.truncatingRemainder(dividingBy: 12.0)) / 12.0
    let rotation = phase * 2 * .pi

    ctx.drawLayer { layer in
      layer.translateBy(x: center.x, y: center.y)
      layer.rotate(by: .radians(rotation))

      let rayColor = GraphicsContext.Shading.color(
        Color(red: 0xc5 / 255, green: 0x48 / 255, blue: 0x2a / 255)
      )
      let inner: CGFloat = 8
      let outer: CGFloat = 11

      for i in 0..<4 {
        let angle = CGFloat(i) * (.pi / 4)
        let dx = cos(angle)
        let dy = sin(angle)
        var ray = Path()
        ray.move(to: CGPoint(x: dx * inner, y: dy * inner))
        ray.addLine(to: CGPoint(x: dx * outer, y: dy * outer))
        layer.stroke(ray, with: rayColor, style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
      }
    }
  }

  private func drawAtomicStar(
    in ctx: inout GraphicsContext,
    center: CGPoint,
    scale: CGFloat,
    period: Double,
    t: TimeInterval
  ) {
    let phase = (t.truncatingRemainder(dividingBy: abs(period))) / abs(period)
    let rotation = phase * 2 * .pi * (period > 0 ? 1 : -1)

    ctx.drawLayer { layer in
      layer.translateBy(x: center.x, y: center.y)
      layer.rotate(by: .radians(rotation))
      layer.scaleBy(x: scale, y: scale)

      let ink = GraphicsContext.Shading.color(
        Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255))
      let stroke = StrokeStyle(lineWidth: 0.8, lineCap: .round)
      let arm: CGFloat = 4

      // plus
      var plus = Path()
      plus.move(to: CGPoint(x: -arm, y: 0))
      plus.addLine(to: CGPoint(x: arm, y: 0))
      plus.move(to: CGPoint(x: 0, y: -arm))
      plus.addLine(to: CGPoint(x: 0, y: arm))
      layer.stroke(plus, with: ink, style: stroke)

      // diagonal cross
      let d: CGFloat = arm * 0.75
      var cross = Path()
      cross.move(to: CGPoint(x: -d, y: -d))
      cross.addLine(to: CGPoint(x: d, y: d))
      cross.move(to: CGPoint(x: -d, y: d))
      cross.addLine(to: CGPoint(x: d, y: -d))
      layer.stroke(cross, with: ink, style: stroke)

      // center dot
      let dot = Path(ellipseIn: CGRect(x: -0.6, y: -0.6, width: 1.2, height: 1.2))
      layer.fill(dot, with: ink)
    }
  }

  private func drawSilhouette(in ctx: inout GraphicsContext, t: TimeInterval) {
    let strollPeriod: Double = 8.0
    let phase = (t.truncatingRemainder(dividingBy: strollPeriod)) / strollPeriod
    let x = -8 + CGFloat(phase) * (vbW + 16)

    let bobPeriod: Double = 0.6
    let bobPhase = (t.truncatingRemainder(dividingBy: bobPeriod)) / bobPeriod
    let bobUp = bobPhase < 0.5

    let ink = GraphicsContext.Shading.color(
      Color(red: 0x05 / 255, green: 0x05 / 255, blue: 0x05 / 255))

    ctx.drawLayer { layer in
      layer.translateBy(x: x, y: 0)

      // head
      let head = Path(ellipseIn: CGRect(x: -1.4, y: 24.0, width: 2.8, height: 2.8))
      layer.fill(head, with: ink)

      // body (trapezoid)
      var body = Path()
      body.move(to: CGPoint(x: -1.6, y: 27))
      body.addLine(to: CGPoint(x: 1.6, y: 27))
      body.addLine(to: CGPoint(x: 1.2, y: 31))
      body.addLine(to: CGPoint(x: -1.2, y: 31))
      body.closeSubpath()
      layer.fill(body, with: ink)

      // legs — alternate y for walk cycle
      let leftY: CGFloat = bobUp ? 31.6 : 32.0
      let rightY: CGFloat = bobUp ? 32.0 : 31.6
      let leftLeg = Path(CGRect(x: -1.1, y: leftY, width: 0.9, height: 4))
      let rightLeg = Path(CGRect(x: 0.2, y: rightY, width: 0.9, height: 4))
      layer.fill(leftLeg, with: ink)
      layer.fill(rightLeg, with: ink)
    }
  }
}
