import Testing
@testable import SwiftVinetas

// MARK: - ImageNetLabelsTests

/// Tests that the ImageNet-1K label list is correct.
@Suite("ImageNetLabels")
struct ImageNetLabelsTests {

    // MARK: Count

    @Test("Has exactly 1000 labels")
    func labelCount() {
        #expect(ImageNetLabels.labels.count == 1000)
    }

    // MARK: Boundary values

    @Test("First label is 'tench'")
    func firstLabel() {
        #expect(ImageNetLabels.labels.first == "tench")
    }

    @Test("Last label is 'ear'")
    func lastLabel() {
        #expect(ImageNetLabels.labels.last == "ear")
    }

    // MARK: Spot-checks

    @Test("Well-known labels exist at expected indices")
    func knownLabels() {
        // Class 1: goldfish
        #expect(ImageNetLabels.labels[1] == "goldfish")
        // Class 2: great white shark
        #expect(ImageNetLabels.labels[2] == "great white shark")
        // Class 207: Golden Retriever (canonical dog class)
        #expect(ImageNetLabels.labels[207] == "Golden Retriever")
        // Class 292: tiger
        #expect(ImageNetLabels.labels[292] == "tiger")
        // Class 998: toilet paper (often called "toilet tissue" in original ImageNet)
        #expect(ImageNetLabels.labels[998] == "toilet paper")
    }

    // MARK: No duplicates

    @Test("No duplicate labels")
    func noDuplicates() {
        let labels = ImageNetLabels.labels
        let unique = Set(labels)
        #expect(unique.count == labels.count, "Duplicate labels found: \(labels.filter { label in labels.filter { $0 == label }.count > 1 })")
    }

    // MARK: Non-empty

    @Test("All labels are non-empty strings")
    func nonEmptyLabels() {
        let emptyLabels = ImageNetLabels.labels.filter { $0.isEmpty }
        #expect(emptyLabels.isEmpty, "Found empty label strings: \(emptyLabels.count)")
    }

    // MARK: Index safety

    @Test("Index range covers 0..<1000")
    func indexRange() {
        for i in 0..<1000 {
            #expect(!ImageNetLabels.labels[i].isEmpty, "Label at index \(i) is empty")
        }
    }
}
