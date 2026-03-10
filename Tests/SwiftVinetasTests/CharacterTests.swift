import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - Slug Derivation Tests

@Suite("Character Slug Derivation")
struct SlugDerivationTests {

    @Test("Simple name with space becomes hyphenated slug")
    func simpleNameToSlug() {
        #expect(Character.deriveSlug(from: "Detective Vale") == "detective-vale")
    }

    @Test("Single word lowercased")
    func singleWordName() {
        #expect(Character.deriveSlug(from: "Vale") == "vale")
    }

    @Test("Multiple spaces collapsed to single hyphens")
    func multipleSpaces() {
        let slug = Character.deriveSlug(from: "John  Doe")
        #expect(slug == "john-doe")
    }

    @Test("Non-alphanumeric characters stripped")
    func specialCharactersStripped() {
        let slug = Character.deriveSlug(from: "Dr. O'Brien!")
        #expect(slug == "dr-obrien")
    }

    @Test("All uppercase converted to lowercase")
    func uppercaseConversion() {
        #expect(Character.deriveSlug(from: "ALICE") == "alice")
    }

    @Test("Trailing and leading hyphens removed")
    func trimmingHyphens() {
        let slug = Character.deriveSlug(from: " Vale ")
        #expect(!slug.hasPrefix("-"))
        #expect(!slug.hasSuffix("-"))
    }
}

// MARK: - Trigger Word Tests

@Suite("Character Trigger Word")
struct TriggerWordTests {

    @Test("Trigger word derived from slug")
    func triggerWordFromSlug() {
        let character = Character(name: "Detective Vale")
        #expect(character.triggerWord == "sks_detective-vale")
    }

    @Test("Trigger word uses sks_ prefix")
    func triggerWordPrefix() {
        let character = Character(name: "Vale")
        #expect(character.triggerWord.hasPrefix("sks_"))
    }

    @Test("Custom slug uses correct trigger word")
    func customSlugTriggerWord() {
        let character = Character(name: "Detective Vale", slug: "vale")
        #expect(character.triggerWord == "sks_vale")
    }

    @Test("Explicit trigger word is preserved")
    func explicitTriggerWord() {
        let character = Character(name: "Vale", triggerWord: "sks_custom")
        #expect(character.triggerWord == "sks_custom")
    }
}

// MARK: - Character Initialization Tests

@Suite("Character Initialization")
struct CharacterInitializationTests {

    @Test("Slug derived from name when not provided")
    func slugDerivedFromName() {
        let character = Character(name: "Detective Vale")
        #expect(character.slug == "detective-vale")
    }

    @Test("Explicit slug preserved")
    func explicitSlugPreserved() {
        let character = Character(name: "Detective Vale", slug: "vale")
        #expect(character.slug == "vale")
    }

    @Test("Default source photos is empty")
    func defaultSourcePhotosEmpty() {
        let character = Character(name: "Vale")
        #expect(character.sourcePhotos.isEmpty)
    }

    @Test("Default description is empty string")
    func defaultDescriptionEmpty() {
        let character = Character(name: "Vale")
        #expect(character.description.isEmpty)
    }

    @Test("Default lora is nil")
    func defaultLoraNil() {
        let character = Character(name: "Vale")
        #expect(character.lora == nil)
    }
}

// MARK: - YAML Round-Trip Tests

@Suite("Character YAML Serialization")
struct CharacterYAMLTests {

    @Test("YAML output contains required keys")
    func yamlContainsRequiredKeys() throws {
        let character = Character(
            name: "Detective Vale",
            slug: "detective-vale",
            created: Date(),
            sourcePhotos: ["source/vale-photo-01.png"],
            description: "Male, 40s, angular jaw"
        )
        let yaml = try character.yamlEncoded()
        #expect(yaml.contains("name"))
        #expect(yaml.contains("slug"))
        #expect(yaml.contains("trigger_word"))
        #expect(yaml.contains("source_photos"))
    }

    @Test("YAML round-trip preserves name")
    func yamlRoundTripName() throws {
        let original = Character(name: "Detective Vale")
        let yaml = try original.yamlEncoded()
        let decoded = try Character.from(yaml: yaml)
        #expect(decoded.name == original.name)
    }

    @Test("YAML round-trip preserves slug")
    func yamlRoundTripSlug() throws {
        let original = Character(name: "Detective Vale")
        let yaml = try original.yamlEncoded()
        let decoded = try Character.from(yaml: yaml)
        #expect(decoded.slug == original.slug)
    }

    @Test("YAML round-trip preserves trigger word")
    func yamlRoundTripTriggerWord() throws {
        let original = Character(name: "Detective Vale")
        let yaml = try original.yamlEncoded()
        let decoded = try Character.from(yaml: yaml)
        #expect(decoded.triggerWord == original.triggerWord)
    }

    @Test("YAML round-trip preserves source photos")
    func yamlRoundTripSourcePhotos() throws {
        let original = Character(
            name: "Vale",
            sourcePhotos: ["source/vale-photo-01.png", "source/vale-photo-02.png"]
        )
        let yaml = try original.yamlEncoded()
        let decoded = try Character.from(yaml: yaml)
        #expect(decoded.sourcePhotos == original.sourcePhotos)
    }

    @Test("YAML round-trip preserves description")
    func yamlRoundTripDescription() throws {
        let original = Character(
            name: "Vale",
            description: "Male, 40s, angular jaw, short dark hair, perpetual stubble"
        )
        let yaml = try original.yamlEncoded()
        let decoded = try Character.from(yaml: yaml)
        #expect(decoded.description == original.description)
    }

    @Test("YAML round-trip with LoRA metadata")
    func yamlRoundTripLoRA() throws {
        let lora = LoRAMetadata(
            path: "lora/vale-v1.safetensors",
            scale: 0.8,
            version: 1,
            trainingSteps: 1500,
            model: .klein4b
        )
        let original = Character(
            name: "Vale",
            lora: lora
        )
        let yaml = try original.yamlEncoded()
        let decoded = try Character.from(yaml: yaml)
        #expect(decoded.lora != nil)
        #expect(decoded.lora?.path == "lora/vale-v1.safetensors")
        #expect(decoded.lora?.scale == 0.8)
        #expect(decoded.lora?.version == 1)
        #expect(decoded.lora?.trainingSteps == 1500)
    }

    @Test("YAML uses snake_case key for trigger word")
    func yamlSnakeCaseTriggerWord() throws {
        let character = Character(name: "Vale")
        let yaml = try character.yamlEncoded()
        #expect(yaml.contains("trigger_word"))
        #expect(!yaml.contains("triggerWord"))
    }

    @Test("YAML uses snake_case key for source_photos")
    func yamlSnakeCaseSourcePhotos() throws {
        let character = Character(name: "Vale", sourcePhotos: ["source/photo.png"])
        let yaml = try character.yamlEncoded()
        #expect(yaml.contains("source_photos"))
        #expect(!yaml.contains("sourcePhotos"))
    }
}

// MARK: - LoRAMetadata Tests

@Suite("LoRAMetadata")
struct LoRAMetadataTests {

    @Test("Default scale is 0.8")
    func defaultScale() {
        let lora = LoRAMetadata(path: "lora/test.safetensors")
        #expect(lora.scale == 0.8)
    }

    @Test("Default version is 1")
    func defaultVersion() {
        let lora = LoRAMetadata(path: "lora/test.safetensors")
        #expect(lora.version == 1)
    }

    @Test("LoRA model stored correctly")
    func loraModelStored() {
        let lora = LoRAMetadata(path: "lora/test.safetensors", model: .klein4b)
        #expect(lora.model == .klein4b)
    }
}

// MARK: - CharacterManager Directory Tests

@Suite("CharacterManager Directory Structure")
struct CharacterManagerDirectoryTests {

    /// Build a CharacterManager rooted in a fresh temp directory.
    private func makeTempManager() -> (CharacterManager, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftVinetasTests-\(UUID().uuidString)", isDirectory: true)
        let manager = CharacterManager(baseDirectory: tmp)
        return (manager, tmp)
    }

    @Test("createCharacter creates expected directory tree")
    func directoryTreeCreated() throws {
        let (manager, _) = makeTempManager()
        let character = try manager.createCharacter(name: "Detective Vale")
        let charDir = manager.characterDirectory(slug: character.slug)

        let fm = FileManager.default
        var isDir: ObjCBool = false

        for sub in ["source", "references", "training", "lora"] {
            let subURL = charDir.appendingPathComponent(sub)
            #expect(fm.fileExists(atPath: subURL.path, isDirectory: &isDir))
            #expect(isDir.boolValue, "'\(sub)' should be a directory")
        }
    }

    @Test("createCharacter writes character.yaml")
    func yamlManifestWritten() throws {
        let (manager, _) = makeTempManager()
        let character = try manager.createCharacter(name: "Detective Vale")
        let yamlURL = manager.characterDirectory(slug: character.slug)
            .appendingPathComponent("character.yaml")
        #expect(FileManager.default.fileExists(atPath: yamlURL.path))
    }

    @Test("createCharacter derives correct slug")
    func correctSlugDerived() throws {
        let (manager, _) = makeTempManager()
        let character = try manager.createCharacter(name: "Detective Vale")
        #expect(character.slug == "detective-vale")
    }

    @Test("createCharacter derives correct trigger word")
    func correctTriggerWord() throws {
        let (manager, _) = makeTempManager()
        let character = try manager.createCharacter(name: "Detective Vale")
        #expect(character.triggerWord == "sks_detective-vale")
    }

    @Test("loadCharacter reads back the saved character")
    func loadCharacterRoundTrip() throws {
        let (manager, _) = makeTempManager()
        let created = try manager.createCharacter(
            name: "Detective Vale",
            description: "Male, 40s, angular jaw"
        )
        let loaded = try manager.loadCharacter(slug: created.slug)
        #expect(loaded.name == created.name)
        #expect(loaded.slug == created.slug)
        #expect(loaded.triggerWord == created.triggerWord)
        #expect(loaded.description == created.description)
    }

    @Test("listCharacters returns created characters")
    func listCharactersReturnsAll() throws {
        let (manager, _) = makeTempManager()
        _ = try manager.createCharacter(name: "Alice")
        _ = try manager.createCharacter(name: "Bob")
        let list = try manager.listCharacters()
        #expect(list.count == 2)
        let slugs = Set(list.map(\.slug))
        #expect(slugs.contains("alice"))
        #expect(slugs.contains("bob"))
    }

    @Test("listCharacters returns empty when base directory missing")
    func listCharactersEmptyWhenMissing() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftVinetasTests-NonExistent-\(UUID().uuidString)")
        let manager = CharacterManager(baseDirectory: tmp)
        let list = try manager.listCharacters()
        #expect(list.isEmpty)
    }

    @Test("deleteCharacter removes the directory")
    func deleteCharacterRemovesDirectory() throws {
        let (manager, _) = makeTempManager()
        let character = try manager.createCharacter(name: "TempChar")
        let charDir = manager.characterDirectory(slug: character.slug)
        #expect(FileManager.default.fileExists(atPath: charDir.path))

        try manager.deleteCharacter(slug: character.slug)
        #expect(!FileManager.default.fileExists(atPath: charDir.path))
    }

    @Test("createCharacter with photo writes PNG to source directory")
    func createCharacterWithPhotoWritesPNG() throws {
        let (manager, _) = makeTempManager()

        // Create a minimal 1x1 CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        let image = context.makeImage()!

        let character = try manager.createCharacter(name: "Vale", photo: image)
        let photoURL = manager.characterDirectory(slug: character.slug)
            .appendingPathComponent("source")
            .appendingPathComponent("vale-photo-01.png")
        #expect(FileManager.default.fileExists(atPath: photoURL.path))
        #expect(character.sourcePhotos == ["source/vale-photo-01.png"])
    }
}

// MARK: - Vinetas Public API Compilation Tests

/// These tests verify that the public Vinetas API compiles correctly.
/// They do not execute the actual implementations (which require disk I/O).
@Suite("Vinetas Character API Compilation")
struct VinetasCharacterAPITests {

    @Test("Character struct can be constructed")
    func characterCanBeConstructed() {
        let character = Character(name: "Test Character")
        #expect(!character.name.isEmpty)
        #expect(!character.slug.isEmpty)
        #expect(character.triggerWord.hasPrefix("sks_"))
    }

    @Test("Vinetas module provides character API symbols")
    func vinetasAPISymbolsAvailable() {
        // Verify method references compile — execution requires disk I/O, so we only check type
        let _createFn: (String, CGImage?, String?, String) throws -> Character = Vinetas.createCharacter
        let _listFn: () throws -> [Character] = Vinetas.listCharacters
        let _loadFn: (String) throws -> Character = Vinetas.loadCharacter
        _ = _createFn
        _ = _listFn
        _ = _loadFn
    }
}
