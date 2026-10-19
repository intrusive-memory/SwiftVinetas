import Testing
import VinetasUI

@Suite struct PanelLayoutResolverTests {

  /// The resolver is a pure function of a named platform and size class, so
  /// every combination runs on the macOS test pass and the iOS one.
  @Test func iOSLayoutFollowsSizeClass() {
    #expect(VinetasPanelLayout.resolve(platform: .iOS, horizontalSizeClass: nil) == .regular)
    #expect(VinetasPanelLayout.resolve(platform: .iOS, horizontalSizeClass: .compact) == .compact)
    #expect(VinetasPanelLayout.resolve(platform: .iOS, horizontalSizeClass: .regular) == .regular)
  }

  @Test func macOSLayoutIsAlwaysSidebar() {
    #expect(VinetasPanelLayout.resolve(platform: .macOS, horizontalSizeClass: nil) == .sidebar)
    #expect(VinetasPanelLayout.resolve(platform: .macOS, horizontalSizeClass: .compact) == .sidebar)
    #expect(VinetasPanelLayout.resolve(platform: .macOS, horizontalSizeClass: .regular) == .sidebar)
  }
}
