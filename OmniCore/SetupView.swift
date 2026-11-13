import SwiftUI

/// Premier lancement, ou serveur injoignable : QR code de l'admin, ou adresse et code saisis à la main.
struct SetupView: View {
    @ObservedObject var store: ServerStore
    @State private var server = ""
    @State private var code = ""
    @State private var invalid = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("OmniCore").font(.largeTitle.bold())

                if let error = store.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(.red)
                        if store.savedServer != nil {
                            Button("Réessayer") { store.retry() }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                        }
                    }
                }

                Text("Le plus simple : dans l’admin d’OmniCore, « Connecter un appareil par QR code », onglet « Application OmniCore ». Scanne le QR code avec l’appareil photo de l’iPhone.")
                Text("Ou saisis l’adresse et le code affichés sous le QR code :")

                TextField("Adresse (ex. 192.168.1.20:3000)", text: $server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                TextField("Code (ex. ABCD-EFGH)", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)

                if invalid {
                    Text("Adresse ou code non valable.").foregroundStyle(.red)
                }

                Button {
                    if let config = PairingConfig.manual(server: server, code: code) {
                        invalid = false
                        store.connect(config)
                    } else {
                        invalid = true
                    }
                } label: {
                    Text("Connecter").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Text("Hors de la maison : installe l’app gratuite Tailscale et connecte-la au réseau privé de la famille.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .onAppear { server = store.savedServer ?? server }
    }
}
