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

    var body: some View {
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
