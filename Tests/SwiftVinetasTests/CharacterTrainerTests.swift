import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - TrainingConfig Default Values

@Suite("TrainingConfig Defaults")
struct TrainingConfigDefaultTests {

    @Test("Default rank is 48")
    func defaultRank() {
        let config = TrainingConfig()
        #expect(config.rank == 48)
    }

    @Test("Default learning rate is 0.001")
    func defaultLearningRate() {
        let config = TrainingConfig()
        #expect(config.learningRate == 0.001)
    }

    @Test("Default steps is 1500")
    func defaultSteps() {
        let config = TrainingConfig()
        #expect(config.steps == 1500)
    }

    @Test("Default batch size is 1")
    func defaultBatchSize() {
        let config = TrainingConfig()
        #expect(config.batchSize == 1)
    }

    @Test("Default weight decay is 0.00015")
    func defaultWeightDecay() {
        let config = TrainingConfig()
        #expect(config.weightDecay == 0.00015)
    }

    @Test("Default gradient checkpointing is true")
    func defaultGradientCheckpointing() {
        let config = TrainingConfig()
        #expect(config.gradientCheckpointing == true)
    }

    @Test("Default quantization is nf4")
    func defaultQuantization() {
        let config = TrainingConfig()
        #expect(config.quantization == "nf4")
    }

    @Test("Custom values override defaults")
    func customValues() {
        let config = TrainingConfig(
            rank: 16,
            learningRate: 0.0001,
            steps: 3000,
            batchSize: 2,
            weightDecay: 0.01,
            gradientCheckpointing: false,
            quantization: "int8"
        )
        #expect(config.rank == 16)
        #expect(config.learningRate == 0.0001)
        #expect(config.steps == 3000)
        #expect(config.batchSize == 2)
        #expect(config.weightDecay == 0.01)
        #expect(config.gradientCheckpointing == false)
        #expect(config.quantization == "int8")
    }
}

// MARK: - Memory Validation Tests

@Suite("CharacterTrainer Memory Validation")
struct CharacterTrainerMemoryTests {

    @Test("Systems with less than 8 GB fail memory validation for Klein 4B nf4")
    func insufficientMemoryFails() {
        let sevenGB: UInt64 = 7 * 1_073_741_824
        let result = CharacterTrainer.validateMemory(
            for: .klein4b,
            quantization: "nf4",
            availableMemoryBytes: sevenGB
        )
        #expect(result == false)
    }

    @Test("Systems with exactly 8 GB pass memory validation")
    func exactlyEightGBPasses() {
        let eightGB: UInt64 = 8 * 1_073_741_824
        let result = CharacterTrainer.validateMemory(
            for: .klein4b,
            quantization: "nf4",
            availableMemoryBytes: eightGB
        )
        #expect(result == true)
    }

    @Test("Systems with 16 GB pass memory validation")
    func sixteenGBPasses() {
        let sixteenGB: UInt64 = 16 * 1_073_741_824
        let result = CharacterTrainer.validateMemory(
            for: .klein4b,
            quantization: "nf4",
            availableMemoryBytes: sixteenGB
        )
        #expect(result == true)
    }

    @Test("Systems with 4 GB fail memory validation")
    func fourGBFails() {
        let fourGB: UInt64 = 4 * 1_073_741_824
        let result = CharacterTrainer.validateMemory(
            for: .klein4b,
            quantization: "nf4",
            availableMemoryBytes: fourGB
        )
        #expect(result == false)
    }

    @Test("Systems with 0 GB fail memory validation")
    func zeroMemoryFails() {
        let result = CharacterTrainer.validateMemory(
            for: .klein4b,
            quantization: "nf4",
            availableMemoryBytes: 0
        )
        #expect(result == false)
    }

    @Test("Klein 9B also requires at least 8 GB for nf4 training")
    func klein9BNf4MinimumMemory() {
        let sevenGB: UInt64 = 7 * 1_073_741_824
        let eightGB: UInt64 = 8 * 1_073_741_824
        #expect(
            CharacterTrainer.validateMemory(
                for: .klein9b,
                quantization: "nf4",
                availableMemoryBytes: sevenGB
            ) == false
        )
        #expect(
            CharacterTrainer.validateMemory(
                for: .klein9b,
                quantization: "nf4",
                availableMemoryBytes: eightGB
            ) == true
        )
    }

    @Test("Minimum training memory constant is 8 GB")
    func minimumTrainingMemoryConstant() {
        #expect(CharacterTrainer.minimumTrainingMemoryGB == 8)
    }
}

// MARK: - Output Path Construction Tests

@Suite("CharacterTrainer Output Path")
struct CharacterTrainerOutputPathTests {

    /// Create a temporary lora directory and return its URL.
    private func makeTempLoraDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftVinetasTests-\(UUID().uuidString)", isDirectory: true)
        let loraDir = tmp.appendingPathComponent("lora", isDirectory: true)
        try FileManager.default.createDirectory(at: loraDir, withIntermediateDirectories: true)
        return loraDir
    }

    @Test("First training produces v1 safetensors")
    func firstTrainingV1() throws {
        let loraDir = try makeTempLoraDir()
        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "detective-vale", in: loraDir)
        #expect(version == 1)

        let path = CharacterTrainer.outputPath(
            slug: "detective-vale",
            version: version,
            loraDirectory: loraDir
        )
        #expect(path.lastPathComponent == "detective-vale-v1.safetensors")
    }

    @Test("Second training produces v2 safetensors")
    func secondTrainingV2() throws {
        let loraDir = try makeTempLoraDir()
        let fm = FileManager.default

        // Create a v1 file
        let v1URL = loraDir.appendingPathComponent("detective-vale-v1.safetensors")
        fm.createFile(atPath: v1URL.path, contents: Data())

        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "detective-vale", in: loraDir)
        #expect(version == 2)

        let path = CharacterTrainer.outputPath(
            slug: "detective-vale",
            version: version,
            loraDirectory: loraDir
        )
        #expect(path.lastPathComponent == "detective-vale-v2.safetensors")
    }

    @Test("Version increments past existing versions")
    func versionIncrementsPastExisting() throws {
        let loraDir = try makeTempLoraDir()
        let fm = FileManager.default

        // Create v1, v2, v3
        for v in 1...3 {
            let url = loraDir.appendingPathComponent("test-char-v\(v).safetensors")
            fm.createFile(atPath: url.path, contents: Data())
        }

        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "test-char", in: loraDir)
        #expect(version == 4)
    }

    @Test("Non-contiguous versions use max + 1")
    func nonContiguousVersions() throws {
        let loraDir = try makeTempLoraDir()
        let fm = FileManager.default

        // Create v1 and v5 (gap in versions)
        for v in [1, 5] {
            let url = loraDir.appendingPathComponent("my-char-v\(v).safetensors")
            fm.createFile(atPath: url.path, contents: Data())
        }

        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "my-char", in: loraDir)
        #expect(version == 6)
    }

    @Test("Different slug files are ignored when computing version")
    func differentSlugIgnored() throws {
        let loraDir = try makeTempLoraDir()
        let fm = FileManager.default

        // Create files for a different character
        let otherURL = loraDir.appendingPathComponent("other-char-v5.safetensors")
        fm.createFile(atPath: otherURL.path, contents: Data())

        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "my-char", in: loraDir)
        #expect(version == 1)
    }

    @Test("Empty directory returns version 1")
    func emptyDirectoryReturnsV1() throws {
        let loraDir = try makeTempLoraDir()
        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "new-char", in: loraDir)
        #expect(version == 1)
    }

    @Test("Non-existent directory returns version 1")
    func nonExistentDirectoryReturnsV1() {
        let loraDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)", isDirectory: true)
        let trainer = CharacterTrainer()
        let version = trainer.nextVersion(slug: "new-char", in: loraDir)
        #expect(version == 1)
    }
}

// MARK: - Training Data Discovery Tests

@Suite("CharacterTrainer Training Data Discovery")
struct CharacterTrainerTrainingDataTests {

    /// Create a temporary training directory with image/caption pairs.
    private func makeTempTrainingDir(
        pairs: [(baseName: String, hasCaption: Bool)] = []
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftVinetasTests-\(UUID().uuidString)", isDirectory: true)
        let trainingDir = tmp.appendingPathComponent("training", isDirectory: true)
        try FileManager.default.createDirectory(at: trainingDir, withIntermediateDirectories: true)

        let fm = FileManager.default
        for pair in pairs {
            let pngURL = trainingDir.appendingPathComponent("\(pair.baseName).png")
            fm.createFile(atPath: pngURL.path, contents: Data([0x89, 0x50, 0x4E, 0x47]))
            if pair.hasCaption {
                let txtURL = trainingDir.appendingPathComponent("\(pair.baseName).txt")
                try "test caption for \(pair.baseName)".write(
                    to: txtURL, atomically: true, encoding: .utf8
                )
            }
        }

        return trainingDir
    }

    @Test("Locates matching png+txt pairs")
    func locatesMatchingPairs() throws {
        let dir = try makeTempTrainingDir(pairs: [
            (baseName: "front", hasCaption: true),
            (baseName: "back", hasCaption: true),
        ])
        let trainer = CharacterTrainer()
        let pairs = try trainer.locateTrainingData(in: dir)
        #expect(pairs.count == 2)
    }

    @Test("Skips png without matching txt")
    func skipsOrphanedPng() throws {
        let dir = try makeTempTrainingDir(pairs: [
            (baseName: "front", hasCaption: true),
            (baseName: "orphan", hasCaption: false),
        ])
        let trainer = CharacterTrainer()
        let pairs = try trainer.locateTrainingData(in: dir)
        #expect(pairs.count == 1)
        #expect(pairs[0].imageURL.lastPathComponent == "front.png")
    }

    @Test("Empty directory returns empty array")
    func emptyDirectoryReturnsEmpty() throws {
        let dir = try makeTempTrainingDir(pairs: [])
        let trainer = CharacterTrainer()
        let pairs = try trainer.locateTrainingData(in: dir)
        #expect(pairs.isEmpty)
    }

    @Test("Non-existent directory returns empty array")
    func nonExistentDirectoryReturnsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)", isDirectory: true)
        let trainer = CharacterTrainer()
        let pairs = try trainer.locateTrainingData(in: dir)
        #expect(pairs.isEmpty)
    }
}

// MARK: - Vinetas Public API Compilation Test

@Suite("Vinetas LoRA Training API")
struct VinetasLoRATrainingAPITests {

    @Test("Vinetas.trainCharacterLoRA compiles and has correct signature")
    func trainCharacterLoRASignatureCompiles() {
        // Verify the method reference compiles with the expected signature.
        // This is an async throws function returning URL, taking Character, TrainingConfig,
        // VinetasModel, and an optional progress callback.
        let _fn: (Character, TrainingConfig, VinetasModel, ((Int, Int, Float) -> Void)?) async throws -> URL =
            Vinetas.trainCharacterLoRA(for:config:model:progress:)
        _ = _fn
    }
}
