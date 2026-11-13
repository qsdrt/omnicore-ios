import AVFoundation
import SwiftUI

@main
struct OmniCoreApp: App {
    @StateObject private var store = ServerStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Sauvegarde des photos : la tâche de fond doit être déclarée avant la fin du lancement.
        PhotoBackup.shared.registerBackgroundTask()
        // Musique et films continuent écran verrouillé, et le bouton silencieux ne coupe pas le son.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if let config = PairingConfig.fromLink(url) { store.connect(config) }
                }
                .onChange(of: scenePhase) { phase in
                    // À chaque ouverture, les nouvelles photos partent ; en quittant, iOS est prié de continuer plus tard.
                    if phase == .active { PhotoBackup.shared.runSoon() }
                    if phase == .background { PhotoBackup.shared.scheduleBackground() }
                }
        }
    }
}

private struct RootView: View {
    @ObservedObject var store: ServerStore
    @State private var expiryWarning = AppExpiry.warning()

    var body: some View {
        VStack(spacing: 0) {
            // Signature gratuite d'Apple : 7 jours. Prévenir 2 jours avant, avec ce qu'il faut faire.
            if let expiryWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text(expiryWarning).font(.footnote)
                    Spacer(minLength: 0)
                    Button { self.expiryWarning = nil } label: { Image(systemName: "xmark") }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Masquer")
                }
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.25))
            }
            if let url = store.startURL {
                BrowserView(url: url, onFailure: store.fail)
                    .id(store.session)
                    .ignoresSafeArea(edges: .bottom)
                    .background(Color.black)
            } else {
                SetupView(store: store)
            }
        }
    }
}
