// TeleprompterTests/Utilities/ReadTimeEstimatorTests.swift
import Testing
@testable import Teleprompter

@Suite("Read Time Estimator")
struct ReadTimeEstimatorTests {

    @Test("estimates duration for a known word count")
    func testBasicEstimate() {
        // Average speaking rate: ~150 words per minute
        let text = String(repeating: "word ", count: 150)
        let duration = ReadTimeEstimator.estimateDuration(for: text, wordsPerMinute: 150)
        #expect(duration == 60.0) // 1 minute
    }

    @Test("returns zero for empty text")
    func testEmptyText() {
        let duration = ReadTimeEstimator.estimateDuration(for: "", wordsPerMinute: 150)
        #expect(duration == 0.0)
    }

    @Test("formats duration as readable string")
    func testFormatDuration() {
        #expect(ReadTimeEstimator.formatDuration(45) == "~45 sec")
        #expect(ReadTimeEstimator.formatDuration(90) == "~1.5 min")
        #expect(ReadTimeEstimator.formatDuration(480) == "~8 min")
    }
}
