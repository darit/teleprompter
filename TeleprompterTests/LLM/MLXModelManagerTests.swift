// TeleprompterTests/LLM/MLXModelManagerTests.swift
import XCTest
@testable import Teleprompter

final class MLXModelManagerTests: XCTestCase {

    // MARK: - MLXModelInfo

    func testRecommendedListIsNotEmpty() {
        XCTAssertFalse(MLXModelInfo.recommended.isEmpty)
    }

    func testRecommendedListIsSortedBySize() {
        let sizes = MLXModelInfo.recommended.map(\.sizeOnDisk)
        for i in 1..<sizes.count {
            XCTAssertGreaterThanOrEqual(sizes[i], sizes[i - 1],
                "Recommended models should be sorted by size ascending")
        }
    }

    func testAllRecommendedRepoIdsAreValid() {
        for model in MLXModelInfo.recommended {
            XCTAssertFalse(model.repoId.isEmpty, "Repo ID should not be empty")
            XCTAssertFalse(model.repoId.contains(" "), "Repo ID should not contain spaces")
            XCTAssertTrue(model.repoId.contains("/"), "Repo ID should contain org/name separator")
        }
    }

    func testBestForThisMachineReturnsModel() {
        let best = MLXModelInfo.bestForThisMachine
        XCTAssertFalse(best.repoId.isEmpty)
        XCTAssertLessThanOrEqual(best.minimumRAM, ProcessInfo.processInfo.physicalMemory)
    }

    func testBestForThisMachineSelectsLargestFitting() {
        let ram = ProcessInfo.processInfo.physicalMemory
        let suitable = MLXModelInfo.recommended.filter { $0.minimumRAM <= ram }
        let best = MLXModelInfo.bestForThisMachine
        // Should be the last (largest) suitable model
        XCTAssertEqual(best.repoId, suitable.last?.repoId)
    }

    // MARK: - MLXModelManager

    func testCanFitInRAM() {
        let manager = MLXModelManager()
        let smallModel = MLXModelInfo.recommended.first!
        XCTAssertTrue(manager.canFitInRAM(smallModel),
            "Smallest model should fit in any test machine's RAM")

        let hugeModel = MLXModelInfo(
            repoId: "test/huge",
            name: "Huge",
            parameterCount: "1T",
            quantization: "fp16",
            sizeOnDisk: 2_000_000_000_000,
            supportsVision: false,
            minimumRAM: 999_000_000_000_000,  // 999 TB
            source: .local
        )
        XCTAssertFalse(manager.canFitInRAM(hugeModel))
    }

    func testSystemRAMDescription() {
        let manager = MLXModelManager()
        let desc = manager.systemRAMDescription
        XCTAssertTrue(desc.contains("GB"), "Should contain 'GB', got: \(desc)")
    }

    func testIsDownloadedReturnsFalseForFakeModel() {
        let manager = MLXModelManager()
        let fake = MLXModelInfo(
            repoId: "fake-org/nonexistent-model-12345",
            name: "Fake",
            parameterCount: "1B",
            quantization: "4-bit",
            sizeOnDisk: 100,
            supportsVision: false,
            minimumRAM: 1,
            source: .recommended
        )
        XCTAssertFalse(manager.isDownloaded(fake))
    }
}
