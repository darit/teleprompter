import SwiftUI
import SwiftData

struct ScriptManagerView: View {
    @State private var selectedScript: Script?

    var body: some View {
        NavigationSplitView {
            ScriptSidebarView(selectedScript: $selectedScript)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let script = selectedScript {
                ScriptDetailView(script: script)
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a script from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
