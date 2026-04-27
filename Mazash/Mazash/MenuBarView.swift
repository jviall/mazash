import SwiftUI

struct MenuBarView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        Button(controller.isListening ? "Stop Listening" : "Start Listening") {
            controller.toggle()
        }

        if let last = controller.lastMatch {
            Divider()
            Text("Last match:")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("\(last.title) - \(last.artist)")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220)
        }

        if let spotify = controller.spotifyService {
            Divider()
            spotifySection(spotify)
        }

        Divider()
        Button("Quit Mazash") { NSApplication.shared.terminate(nil) }
    }

    @ViewBuilder
    private func spotifySection(_ spotify: SpotifyService) -> some View {
        switch spotify.authState {
        case .disconnected:
            Button("Connect Spotify") { spotify.connect() }
        case .authenticating:
            Button("Connecting to Spotify…") { }
                .disabled(true)
        case .connected:
            Text("Spotify: \(spotify.userName ?? "Authenticated")")
                .foregroundStyle(.secondary)
                .font(.caption)
            Button("Disconnect Spotify") { spotify.disconnect() }
        }
    }
}
