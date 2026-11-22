#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftTerm

/// Pane output must not make the terminal allocate past `imageMaxBytes`.
final class ImageLimitTests {
    private final class Recorder: TerminalDelegate {
        var inlineImages = 0
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
        func createImage(source: Terminal, data: Data, width: ImageSizeRequest,
                         height: ImageSizeRequest, preserveAspectRatio: Bool) {
            inlineImages += 1
        }
    }

    private func headless(limit: Int? = nil) -> HeadlessTerminal {
        var options = TerminalOptions(cols: 80, rows: 25)
        if let limit { options.imageMaxBytes = limit }
        return HeadlessTerminal(queue: SwiftTermTests.queue, options: options) { _ in }
    }

    private func sixel(repeat count: String) -> String {
        "\u{1b}Pq#0;2;100;0;0#0!\(count)~\u{1b}\\"
    }

    @Test func sixelUnderTheLimitStillDraws() {
        let h = headless(limit: 1024 * 1024)
        h.terminal.feed(text: sixel(repeat: "10"))
        #expect(h.images.count == 1)
        #expect(h.images.first?.1 == 10)
    }

    @Test func sixelOverTheLimitIsDropped() {
        let h = headless(limit: 1024 * 1024)
        h.terminal.feed(text: sixel(repeat: "100000"))
        #expect(h.images.isEmpty)
    }

    @Test func sixelOverTheDefaultLimitIsDropped() {
        let h = headless()
        h.terminal.feed(text: sixel(repeat: "20000000"))
        #expect(h.images.isEmpty)
    }

    @Test func sixelRepeatCountPastIntIsDropped() {
        let h = headless()
        h.terminal.feed(text: sixel(repeat: "99999999999999999999999"))
        #expect(h.images.isEmpty)
    }

    @Test func sixelBodyOverTheLimitIsDropped() {
        let h = headless(limit: 64)
        h.terminal.feed(text: "\u{1b}Pq#0;2;100;0;0" + String(repeating: "#0~", count: 100) + "\u{1b}\\")
        #expect(h.images.isEmpty)
    }

    @Test func kittyOverTheLimitIsRefused() {
        let h = headless(limit: 1000)
        let payload = Data(repeating: 0xff, count: 20 * 20 * 3).base64EncodedString()
        h.terminal.feed(text: "\u{1b}_Gf=24,s=20,v=20,t=d,i=1;\(payload)\u{1b}\\")
        #expect(h.terminal.kittyGraphicsState.imagesById[1] == nil)
    }

    @Test func kittyUnderTheLimitLoads() {
        let h = headless(limit: 4000)
        let payload = Data(repeating: 0xff, count: 20 * 20 * 3).base64EncodedString()
        h.terminal.feed(text: "\u{1b}_Gf=24,s=20,v=20,t=d,i=1;\(payload)\u{1b}\\")
        #expect(h.terminal.kittyGraphicsState.imagesById[1] != nil)
    }

    private func png(side: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func inline(_ data: Data, limit: Int) -> Int {
        let recorder = Recorder()
        var options = TerminalOptions(cols: 80, rows: 25)
        options.imageMaxBytes = limit
        let terminal = Terminal(delegate: recorder, options: options)
        terminal.feed(text: "\u{1b}]1337;File=inline=1:\(data.base64EncodedString())\u{07}")
        return recorder.inlineImages
    }

    @Test func inlineFileUnderTheLimitDraws() throws {
        #expect(inline(try png(side: 50), limit: 50 * 50 * 4) == 1)
    }

    @Test func inlineFileWhosePixelsPassTheLimitIsDropped() throws {
        let data = try png(side: 200)
        #expect(data.count < 200 * 200 * 4)
        #expect(inline(data, limit: 200 * 200 * 4 - 1) == 0)
    }

    @Test func inlineFileBodyOverTheLimitIsDropped() {
        #expect(inline(Data(repeating: 7, count: 4000), limit: 1000) == 0)
    }
}
#endif
