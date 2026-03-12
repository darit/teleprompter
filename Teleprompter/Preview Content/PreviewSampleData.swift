// Teleprompter/Preview Content/PreviewSampleData.swift
import Foundation
import SwiftData

@MainActor
enum PreviewSampleData {
    static let sampleSections: [ScriptSection] = [
        ScriptSection(
            slideNumber: 1, label: "Introduction",
            content: "Buenas tardes a todos. Hoy vamos a revisar los cambios mas importantes que hicimos en la arquitectura durante Q1.",
            order: 0, accentColorHex: "#4A9EFF"
        ),
        ScriptSection(
            slideNumber: 2, label: "Overview",
            content: "Nos enfocamos en tres pilares: performance, developer experience, y observabilidad.",
            order: 1, accentColorHex: "#34C759"
        ),
        ScriptSection(
            slideNumber: 3, label: "Latency Reduction",
            content: "Logramos reducir la latencia p95 de 320 milisegundos a 180. Eso es una mejora del 44 por ciento gracias a la migracion a Redis Cluster.",
            order: 2, accentColorHex: "#FF9500", isAIRefined: true
        ),
    ]

    static func sampleScript() -> Script {
        let script = Script(name: "Q1 Architecture Review")
        script.sections = sampleSections
        return script
    }

    static var container: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Script.self, ScriptSection.self, configurations: config)
        let script = sampleScript()
        container.mainContext.insert(script)
        return container
    }
}
