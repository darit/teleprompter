// Teleprompter/Views/ScriptManager/ScriptRowView.swift
import SwiftUI
import SwiftData

struct ScriptRowView: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(script.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text(script.modifiedAt, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ScriptRowView(script: PreviewSampleData.sampleScript())
        .padding()
        .modelContainer(PreviewSampleData.container)
}
