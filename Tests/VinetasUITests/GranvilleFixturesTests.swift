import Foundation
import Testing
import VinetasVocabulary

@Suite struct GranvilleFixturesTests {

  @Test func thirteenPanels() throws {
    #expect(try GranvilleFixtures.panels().count == 13)
  }

  @Test func fourteenShotDirectives() throws {
    #expect(try GranvilleFixtures.shotDirectives().count == 14)
  }

  @Test func defaultsShotCarriesTheEpisodeDefaults() throws {
    let defaults = try GranvilleFixtures.defaultsShot
    #expect(defaults["model"] == "klein4b")
    #expect(defaults["aspect"] == "wide")
    #expect(defaults["prompt"] == nil)
  }

  @Test func establishingShotPointsAtItsPanel() throws {
    let shot = try GranvilleFixtures.establishingShot
    #expect(shot["output"] == "storyboards/ep1_sc1_01_establishing.png")
  }

  @Test func establishingPanelUsesKlein4B() throws {
    let panel = try GranvilleFixtures.establishingPanel
    #expect(panel.seed == 22)
    #expect(panel.model == ModelSummary.klein4B.id)
  }
}
