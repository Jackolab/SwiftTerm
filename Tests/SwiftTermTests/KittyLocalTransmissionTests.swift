import Foundation
import Testing

@testable import SwiftTerm

/// With `kittyLocalTransmissions` off, a kitty image may come only inline:
/// file, temporary-file and shared-memory loads open nothing and answer ENOTSUP.
final class KittyLocalTransmissionTests {
    private func makeTerminal() -> (Terminal, TerminalTestDelegate) {
        let delegate = TerminalTestDelegate()
        var options = TerminalOptions(cols: 10, rows: 5)
        options.kittyLocalTransmissions = false
        return (Terminal(delegate: delegate, options: options), delegate)
    }

    private func send(_ t: Terminal, _ control: String, _ payload: Data) {
        t.feed(text: "\u{1b}_G\(control);\(payload.base64EncodedString())\u{1b}\\")
    }

    private func replies(_ d: TerminalTestDelegate) -> String {
        d.sentData.map { String(decoding: $0, as: UTF8.self) }.joined()
    }

    private func tempFile(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftterm-kitty-local-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    @Test func fileTransmissionIsRefused() throws {
        let (t, d) = makeTerminal()
        let url = try tempFile("image.data")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        send(t, "a=t,f=24,s=1,v=1,t=f,i=1", Data(url.path.utf8))
        #expect(t.kittyGraphicsState.imagesById[1] == nil)
        #expect(replies(d).contains("ENOTSUP"))
    }

    @Test func temporaryFileIsRefusedAndKept() throws {
        let (t, d) = makeTerminal()
        let url = try tempFile("tty-graphics-protocol-test.data")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        send(t, "a=t,f=24,s=1,v=1,t=t,i=1", Data(url.path.utf8))
        #expect(t.kittyGraphicsState.imagesById[1] == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(replies(d).contains("ENOTSUP"))
    }

    @Test func missingFileAnswersLikeAnExistingOne() {
        let (t, d) = makeTerminal()
        send(t, "a=t,f=24,s=1,v=1,t=f,i=1", Data("/nonexistent/tenax-probe".utf8))
        #expect(replies(d).contains("ENOTSUP"))
    }

    @Test func sharedMemoryIsRefused() {
        let (t, d) = makeTerminal()
        send(t, "a=t,f=24,s=1,v=1,t=s,i=1", Data("/swiftterm-kitty-probe".utf8))
        #expect(t.kittyGraphicsState.imagesById[1] == nil)
        #expect(replies(d).contains("ENOTSUP"))
    }

    @Test func directImageStillLoads() {
        let (t, _) = makeTerminal()
        send(t, "a=t,f=24,s=1,v=1,t=d,i=1", Data([40, 50, 60]))
        #expect(t.kittyGraphicsState.imagesById[1] != nil)
    }
}
