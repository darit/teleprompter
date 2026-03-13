// Teleprompter/Views/ScriptManager/ScriptRowView.swift
import SwiftUI
import SwiftData

struct ScriptRowView: View {
    let script: Script

    private var formattedDate: String {
        let interval = Date.now.timeIntervalSince(script.modifiedAt)
        switch interval {
        case ..<60:
            return "Just now"
        case ..<3600:
            let mins = Int(interval / 60)
            return "\(mins) min ago"
        case ..<86400:
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        default:
            return script.modifiedAt.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(script.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text(formattedDate)
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
