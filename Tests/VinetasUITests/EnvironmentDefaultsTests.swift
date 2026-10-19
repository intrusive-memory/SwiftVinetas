import SwiftUI
import Testing
import VinetasUI

@Suite struct EnvironmentDefaultsTests {

  @Test func panelLayoutDefaultsToResolve() {
    #expect(EnvironmentValues().vinetasPanelLayout == nil)
  }

  @Test func stylePickerStyleDefaultsToAutomatic() {
    #expect(EnvironmentValues().vinetasStylePickerStyle == .automatic)
  }

  @Test func navigationStackDefaultsToAvailable() {
    #expect(EnvironmentValues().vinetasNavigationStackAvailable == true)
  }
}
