// Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.

// Renders the 1024×1024 app icon: the Fixkey "text + check" symbol on green.
// Usage: swift Tools/app-icon/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//        then drop the alpha channel: magick AppIcon.png -alpha off AppIcon.png
import AppKit
import SwiftUI

struct IconView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.76, blue: 0.57), Color(red: 0.04, green: 0.50, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 520, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render(to path: String) {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("Render failed") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

MainActor.assumeIsolated { render(to: CommandLine.arguments[1]) }
