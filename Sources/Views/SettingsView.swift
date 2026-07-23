import SwiftUI

/// This app's only Settings pane so far: the TMDB API key used by
/// AddTVEpisodeSheet's and AddVideoSheet's "Look Up Online" buttons
/// (TMDBMetadataFetcher). Standard macOS Settings scene, opened via the app
/// menu or ⌘,.
struct SettingsView: View {
    @State private var apiKeyInput: String = ""
    @State private var hasStoredKey = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField("TMDB API Key", text: $apiKeyInput)
                Text(hasStoredKey ? "An API key is currently stored in the Keychain." : "No API key stored yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Used by the TV Shows tab's \"Look Up Online\" button to confirm show/episode names. Get a free key by registering at themoviedb.org, under Settings > API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Clear", role: .destructive) { clear() }
                        .disabled(!hasStoredKey)
                    Button("Save") { save() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("TMDB Integration")
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: refreshStatus)
    }

    private func refreshStatus() {
        hasStoredKey = KeychainStore.get(
            service: TMDBMetadataFetcher.apiKeyKeychainService,
            account: TMDBMetadataFetcher.apiKeyKeychainAccount
        ) != nil
    }

    private func save() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.set(trimmed, service: TMDBMetadataFetcher.apiKeyKeychainService, account: TMDBMetadataFetcher.apiKeyKeychainAccount)
            apiKeyInput = ""
            statusMessage = "Saved."
            refreshStatus()
        } catch {
            statusMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func clear() {
        KeychainStore.delete(service: TMDBMetadataFetcher.apiKeyKeychainService, account: TMDBMetadataFetcher.apiKeyKeychainAccount)
        statusMessage = "Cleared."
        refreshStatus()
    }
}
