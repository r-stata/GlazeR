// GlazeR — 图标生成（AppKit 绘图，无外部依赖）
// 运行：swift build/make_icons.swift
// 产出：App 图标 build/icon.png / icon.iconset / icon.icns、菜单栏 menubar.png，
//       .glazer 文档图标 build/glazer-doc.png / glazer-doc.iconset / glazer-doc.icns
import AppKit
import CoreGraphics
import Foundation

let scriptPath = (#filePath as NSString).deletingLastPathComponent as String   // build/
let root = (scriptPath as NSString).deletingLastPathComponent
let buildDir = (root as NSString).appendingPathComponent("build")
let iconsetDir = (buildDir as NSString).appendingPathComponent("icon.iconset")

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("!! 无法写出 \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
    print("   \(path)")
}

func wedgePath(center: CGPoint, radius: CGFloat, startDeg: CGFloat, endDeg: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: center)
    let step: CGFloat = 2
    var d = startDeg
    while d < endDeg {
        let a = (d - 90) * .pi / 180
        p.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
        d += step
    }
    let a = (endDeg - 90) * .pi / 180
    p.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
    p.closeSubpath()
    return p
}

/// 应用图标：紫色渐变圆角方底 + 6 个白色楔形扇区 + 中心「R」
func appIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let r = size * 0.225
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: size * 0.045, dy: size * 0.045),
                       cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let top = CGColor(srgbRed: 0.365, green: 0.322, blue: 0.945, alpha: 1)
    let bottom = CGColor(srgbRed: 0.208, green: 0.302, blue: 0.878, alpha: 1)
    if let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    }

    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.355
    let hub = size * 0.145
    let n = 6
    let span = 360 / CGFloat(n)
    let alphas: [CGFloat] = [0.95, 0.78, 0.62, 0.88, 0.70, 0.52]

    // 扇区底盘（半透明白）
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
    ctx.addPath(wedgePath(center: center, radius: radius, startDeg: 0, endDeg: 360))
    ctx.fillPath()

    for i in 0..<n {
        let a0 = CGFloat(i) * span + 1.4
        let a1 = CGFloat(i + 1) * span - 1.4
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alphas[i]))
        // 环形扇区：外楔减去中心圆（用 even-odd 填充）
        let p = CGMutablePath()
        p.addPath(wedgePath(center: center, radius: radius, startDeg: a0, endDeg: a1))
        p.addEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
        ctx.addPath(p)
        ctx.fillPath(using: .evenOdd)
    }

    // 中心圆 + 字母 R
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
    let fontSize = size * 0.185
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 0.31, green: 0.275, blue: 0.90, alpha: 1),
    ]
    let s = NSAttributedString(string: "R", attributes: attrs)
    let sz = s.size()
    s.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2 - size * 0.005))

    img.unlockFocus()
    return img
}

/// 菜单栏模板图标：黑色环形 + 6 个扇区缺口
func menubarIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    let center = CGPoint(x: size / 2, y: size / 2)
    let outer = size * 0.44
    let hub = size * 0.17
    let n = 6
    let span = 360 / CGFloat(n)
    ctx.setFillColor(NSColor.black.cgColor)
    for i in 0..<n {
        let a0 = CGFloat(i) * span + 6
        let a1 = CGFloat(i + 1) * span - 6
        let p = CGMutablePath()
        p.addPath(wedgePath(center: center, radius: outer, startDeg: a0, endDeg: a1))
        p.addEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
        ctx.addPath(p)
        ctx.fillPath(using: .evenOdd)
    }
    img.unlockFocus()
    return img
}

/// .glazer 文档图标：白色折角纸张 + 紫色渐变六扇区转盘 + GLAZER 标签
/// 与 App 图标共用 wedgePath，保证两种图标是同一套视觉语言
func docIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    let k = size / 1024
    ctx.scaleBy(x: k, y: k)   // 以下一律按 1024×1024 画布作图

    let paper = CGRect(x: 128, y: 72, width: 768, height: 880)
    let radius: CGFloat = 62
    let fold: CGFloat = 168
    let x1 = paper.maxX, y0 = paper.minY, y1 = paper.maxY
    let paperPath = CGPath(roundedRect: paper, cornerWidth: radius,
                           cornerHeight: radius, transform: nil)
    let cs = CGColorSpaceCreateDeviceRGB()

    // 投影
    ctx.setFillColor(CGColor(srgbRed: 0.18, green: 0.16, blue: 0.34, alpha: 0.15))
    ctx.addPath(CGPath(roundedRect: paper.offsetBy(dx: 0, dy: -16),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    // 纸张本体：白色到极浅蓝的纵向渐变
    ctx.addPath(paperPath)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.saveGState()
    ctx.addPath(paperPath); ctx.clip()
    if let g = CGGradient(colorsSpace: cs,
                          colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                   CGColor(srgbRed: 0.963, green: 0.967, blue: 0.992, alpha: 1)] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y1), end: CGPoint(x: 0, y: y0), options: [])
    }
    ctx.restoreGState()
    ctx.addPath(paperPath)
    ctx.setStrokeColor(CGColor(srgbRed: 0.83, green: 0.84, blue: 0.90, alpha: 1))
    ctx.setLineWidth(4); ctx.strokePath()

    // 右上角：挖掉一块三角，再补上浅灰折页背面
    let cut = CGMutablePath()
    cut.move(to: CGPoint(x: x1 - fold, y: y1))
    cut.addLine(to: CGPoint(x: x1, y: y1))
    cut.addLine(to: CGPoint(x: x1, y: y1 - fold))
    cut.closeSubpath()
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    ctx.addPath(cut); ctx.fillPath()
    // 圆角矩形描边在折角边界外侧还留着半根线宽，单独擦掉，避免两根孤立细线
    ctx.fill(CGRect(x: x1 - fold - 8, y: y1 - 1, width: fold + 16, height: 10))
    ctx.fill(CGRect(x: x1 - 1, y: y1 - fold - 8, width: 10, height: fold + 16))
    ctx.restoreGState()

    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: x1 - fold, y: y1))
    flap.addLine(to: CGPoint(x: x1 - fold, y: y1 - fold))
    flap.addLine(to: CGPoint(x: x1, y: y1 - fold))
    flap.closeSubpath()
    ctx.setFillColor(CGColor(srgbRed: 0.878, green: 0.888, blue: 0.953, alpha: 1))
    ctx.addPath(flap); ctx.fillPath()
    let edge = CGMutablePath()
    edge.move(to: CGPoint(x: x1 - fold, y: y1))
    edge.addLine(to: CGPoint(x: x1, y: y1 - fold))
    ctx.addPath(edge)
    ctx.setStrokeColor(CGColor(srgbRed: 0.76, green: 0.78, blue: 0.87, alpha: 1))
    ctx.setLineWidth(4); ctx.strokePath()

    // 顶部：三行「配置文本」示意线（避开折角区域）
    ctx.setFillColor(CGColor(srgbRed: 0.82, green: 0.84, blue: 0.90, alpha: 1))
    for (y, w) in [(CGFloat(876), CGFloat(300)), (836, 420), (796, 250)] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: 210, y: y, width: w, height: 15),
                           cornerWidth: 7.5, cornerHeight: 7.5, transform: nil))
        ctx.fillPath()
    }
    ctx.setFillColor(CGColor(srgbRed: 0.365, green: 0.322, blue: 0.945, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 210, y: 876, width: 96, height: 15),
                       cornerWidth: 7.5, cornerHeight: 7.5, transform: nil))
    ctx.fillPath()

    // 紫色渐变转盘底盘
    let center = CGPoint(x: 512, y: 520)
    let outer: CGFloat = 236
    let disc = CGRect(x: center.x - outer, y: center.y - outer,
                      width: outer * 2, height: outer * 2)
    ctx.saveGState()
    ctx.addEllipse(in: disc); ctx.clip()
    if let g = CGGradient(colorsSpace: cs,
                          colors: [CGColor(srgbRed: 0.42, green: 0.35, blue: 0.96, alpha: 1),
                                   CGColor(srgbRed: 0.20, green: 0.30, blue: 0.88, alpha: 1)] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: disc.maxY),
                               end: CGPoint(x: 0, y: disc.minY), options: [])
    }
    ctx.restoreGState()

    // 6 个白色环形扇区
    let n = 6, span = 360 / CGFloat(n)
    let alphas: [CGFloat] = [0.95, 0.76, 0.60, 0.88, 0.68, 0.50]
    let hub: CGFloat = 68
    for i in 0..<n {
        let a0 = CGFloat(i) * span + 2.0
        let a1 = CGFloat(i + 1) * span - 2.0
        let p = CGMutablePath()
        p.addPath(wedgePath(center: center, radius: 196, startDeg: a0, endDeg: a1))
        p.addEllipse(in: CGRect(x: center.x - hub, y: center.y - hub,
                                width: hub * 2, height: hub * 2))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alphas[i]))
        ctx.addPath(p); ctx.fillPath(using: .evenOdd)
    }
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub,
                               width: hub * 2, height: hub * 2))
    let rAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 96, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 0.31, green: 0.275, blue: 0.90, alpha: 1),
    ]
    let rText = NSAttributedString(string: "R", attributes: rAttrs)
    let rSize = rText.size()
    rText.draw(at: NSPoint(x: center.x - rSize.width / 2,
                           y: center.y - rSize.height / 2 - 6))

    // 底部标签
    let badge = CGRect(x: 322, y: 158, width: 380, height: 92)
    ctx.setFillColor(CGColor(srgbRed: 0.29, green: 0.26, blue: 0.90, alpha: 1))
    ctx.addPath(CGPath(roundedRect: badge, cornerWidth: 46, cornerHeight: 46, transform: nil))
    ctx.fillPath()
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 50, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: NSNumber(value: 2.5),
    ]
    let title = NSAttributedString(string: "GLAZER", attributes: titleAttrs)
    let tSize = title.size()
    title.draw(at: NSPoint(x: badge.midX - tSize.width / 2,
                           y: badge.midY - tSize.height / 2 - 3))
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 25, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.55, green: 0.57, blue: 0.66, alpha: 1),
    ]
    let sub = NSAttributedString(string: ".glazer · 转盘配置", attributes: subAttrs)
    let sSize = sub.size()
    sub.draw(at: NSPoint(x: 512 - sSize.width / 2, y: 112))

    img.unlockFocus()
    return img
}

func makeICNS(_ setPath: String, _ outPath: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", setPath, "-o", outPath]
    try? task.run()
    task.waitUntilExit()
}

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
let docIconsetDir = (buildDir as NSString).appendingPathComponent("glazer-doc.iconset")
try? FileManager.default.createDirectory(atPath: docIconsetDir, withIntermediateDirectories: true)

let big = appIcon(size: 1024)
writePNG(big, to: (buildDir as NSString).appendingPathComponent("icon.png"))

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, s) in sizes {
    let img = s == 1024 ? big : appIcon(size: s)
    writePNG(img, to: (iconsetDir as NSString).appendingPathComponent(name))
}

let docBig = docIcon(size: 1024)
writePNG(docBig, to: (buildDir as NSString).appendingPathComponent("glazer-doc.png"))
for (name, s) in sizes {
    let img = s == 1024 ? docBig : docIcon(size: s)
    writePNG(img, to: (docIconsetDir as NSString).appendingPathComponent(name))
}

writePNG(menubarIcon(size: 36), to: (buildDir as NSString).appendingPathComponent("menubar.png"))

makeICNS(iconsetDir, (buildDir as NSString).appendingPathComponent("icon.icns"))
makeICNS(docIconsetDir, (buildDir as NSString).appendingPathComponent("glazer-doc.icns"))
print("完成：App 图标与 .glazer 文档图标已生成到 \(buildDir)")
