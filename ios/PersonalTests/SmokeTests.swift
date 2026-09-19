import SwiftUI
import Testing

@testable import Personal

struct SmokeTests {
    @Test func themeHasInk() {
        #expect(Theme.Colors.ink != .clear)
    }
}
