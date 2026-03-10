import Foundation
import Testing

@testable import SwiftVinetas

@Suite("Cosine Similarity Tests")
struct CosineSimilarityTests {

    // MARK: - Identical Vectors

    @Test("Identical vectors return 1.0")
    func identicalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [1, 0, 0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - 1.0) < 1e-6)
    }

    @Test("Identical non-unit vectors return 1.0")
    func identicalNonUnitVectors() {
        let a: [Float] = [3, 4, 0]
        let b: [Float] = [3, 4, 0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - 1.0) < 1e-6)
    }

    // MARK: - Orthogonal Vectors

    @Test("Orthogonal vectors return 0.0")
    func orthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result) < 1e-6)
    }

    @Test("Orthogonal vectors in different axes return 0.0")
    func orthogonalVectorsDifferentAxes() {
        let a: [Float] = [0, 1, 0]
        let b: [Float] = [0, 0, 1]
        let result = cosineSimilarity(a, b)
        #expect(abs(result) < 1e-6)
    }

    // MARK: - Opposite Vectors

    @Test("Opposite vectors return -1.0")
    func oppositeVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [-1, 0, 0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - (-1.0)) < 1e-6)
    }

    @Test("Opposite non-unit vectors return -1.0")
    func oppositeNonUnitVectors() {
        let a: [Float] = [3, 4, 0]
        let b: [Float] = [-3, -4, 0]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - (-1.0)) < 1e-6)
    }

    // MARK: - Zero Vectors

    @Test("Zero vector with non-zero vector returns 0.0")
    func zeroVectorWithNonZero() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [1, 2, 3]
        let result = cosineSimilarity(a, b)
        #expect(result == 0.0)
    }

    @Test("Both zero vectors return 0.0")
    func bothZeroVectors() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [0, 0, 0]
        let result = cosineSimilarity(a, b)
        #expect(result == 0.0)
    }

    // MARK: - Arbitrary Vectors

    @Test("Arbitrary vectors produce expected result")
    func arbitraryVectors() {
        // a = [1, 2, 3], b = [4, 5, 6]
        // dot = 4 + 10 + 18 = 32
        // |a| = sqrt(1+4+9) = sqrt(14)
        // |b| = sqrt(16+25+36) = sqrt(77)
        // similarity = 32 / (sqrt(14) * sqrt(77)) = 32 / sqrt(1078)
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [4, 5, 6]
        let result = cosineSimilarity(a, b)
        let expected: Float = 32.0 / Float(1078.0).squareRoot()
        #expect(abs(result - expected) < 1e-5)
    }

    @Test("Parallel vectors with different magnitudes return 1.0")
    func parallelVectorsDifferentMagnitudes() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [2, 4, 6]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - 1.0) < 1e-6)
    }

    // MARK: - Edge Cases

    @Test("Empty vectors return 0.0")
    func emptyVectors() {
        let a: [Float] = []
        let b: [Float] = []
        let result = cosineSimilarity(a, b)
        #expect(result == 0.0)
    }

    @Test("Mismatched length vectors return 0.0")
    func mismatchedLengthVectors() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [1, 2]
        let result = cosineSimilarity(a, b)
        #expect(result == 0.0)
    }

    @Test("Single-element vectors work correctly")
    func singleElementVectors() {
        let a: [Float] = [5]
        let b: [Float] = [3]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - 1.0) < 1e-6)
    }

    @Test("Single-element opposite vectors return -1.0")
    func singleElementOppositeVectors() {
        let a: [Float] = [5]
        let b: [Float] = [-3]
        let result = cosineSimilarity(a, b)
        #expect(abs(result - (-1.0)) < 1e-6)
    }
}
