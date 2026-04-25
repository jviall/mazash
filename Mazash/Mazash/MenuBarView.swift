import SwiftUI

struct MenuBarView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        Button(controller.isListening ? "Stop Listening" : "Start Listening") {
            controller.toggle()
        }

        if let last = controller.store.lastMatch {
            Divider()
            Text("Last match:")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("\(last.title) - \(last.artist)")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220)
        }

        Divider()
        Button("Quit Mazash") { NSApplication.shared.terminate(nil) }
    }
}
