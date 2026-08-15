#!/usr/bin/env swift

import AppKit
import Foundation

private struct Glyph {
    let source: String
    let outputDirectory: String
}

private let glyphs = [
    Glyph(
        source: "scripts/provider-glyphs/zai.svg",
        outputDirectory: "Sources/Providers/ZAI/Resources"
    ),
    Glyph(
        source: "scripts/provider-glyphs/claude-code.svg",
        outputDirectory: "Sources/Providers/ClaudeCode/Resources"
    ),
    Glyph(
        source: "scripts/provider-glyphs/deepseek.svg",
        outputDirectory: "Sources/Providers/DeepSeek/Resources"
    ),
    Glyph(
        source: "scripts/provider-glyphs/openai-codex.svg",
        outputDirectory: "Sources/Providers/OpenAICodex/Resources"
    ),
    Glyph(
        source: "scripts/provider-glyphs/opencode.svg",
        outputDirectory: "Sources/Providers/OpenCodeGo/Resources"
    ),
]

private let fileManager = FileManager.default
private let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)

private func render(source: URL, pixelSize: Int) throws -> Data {
    guard let image = NSImage(contentsOf: source) else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: source])
    }

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

    let inset = CGFloat(pixelSize) / 8
    let target = NSRect(
        x: inset,
        y: inset,
        width: CGFloat(pixelSize) - (inset * 2),
        height: CGFloat(pixelSize) - (inset * 2)
    )
    image.draw(
        in: target,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

private func generate(_ glyph: Glyph) throws {
    let source = repositoryRoot.appendingPathComponent(glyph.source)
    let outputDirectory = repositoryRoot.appendingPathComponent(glyph.outputDirectory)
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for (filename, pixelSize) in [("ProviderGlyph.png", 24), ("ProviderGlyph@2x.png", 48)] {
        let data = try render(source: source, pixelSize: pixelSize)
        try data.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
    }
}

do {
    for glyph in glyphs {
        try generate(glyph)
    }
} catch {
    FileHandle.standardError.write(Data("Provider glyph generation failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
