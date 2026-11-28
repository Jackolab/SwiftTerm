#if os(macOS)
import Metal
import Testing

@testable import SwiftTerm

@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct MetalLibraryCacheTests {
    /// Each new terminal view makes a renderer; finding and loading the
    /// shader library again for each one costs a bundle search.
    @Test func aSecondRendererReusesTheShaderLibrary() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let first = try MetalTerminalRenderer.makeLibrary(device: device)
        let second = try MetalTerminalRenderer.makeLibrary(device: device)
        #expect(first === second)
    }
}
#endif
