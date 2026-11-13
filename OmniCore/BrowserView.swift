import SwiftUI
import WebKit

/// OmniCore en plein écran. Les pages du serveur restent dans l'app ; un lien extérieur s'ouvre dans Safari.
struct BrowserView: UIViewRepresentable {
    let url: URL
    let onFailure: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(home: url.host, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = "OmniCoreApp/1.0"
        if #available(iOS 16.4, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
        // Pont avec la page Photos : même interface que l'app Android (window.OmniCoreApp).
        configuration.userContentController.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "omnicore")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        context.coordinator.startStatusUpdates(view)
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stopStatusUpdates()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "omnicore")
    }

    private static let bridgeScript = """
    (function () {
      window.__omnicoreBackupStatus = '{}';
      var post = function (message) { window.webkit.messageHandlers.omnicore.postMessage(message); };
      window.OmniCoreApp = {
        backupStatus: function () { return window.__omnicoreBackupStatus; },
        enableBackup: function (token, includeExisting, wifiOnly) { post({ action: 'enable', token: String(token), includeExisting: !!includeExisting, wifiOnly: !!wifiOnly }); },
        backupNow: function () { post({ action: 'now' }); },
        disableBackup: function () { post({ action: 'disable' }); }
      };
    })();
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let home: String?
        private let onFailure: @MainActor (String) -> Void

        init(home: String?, onFailure: @escaping @MainActor (String) -> Void) {
            self.home = home
            self.onFailure = onFailure
        }

        private var statusTimer: Timer?

        /// L'état de la sauvegarde est poussé dans la page toutes les 2 s (lu par la carte « Sauvegarde automatique »).
        func startStatusUpdates(_ view: WKWebView) {
            statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak view] _ in
                let status = PhotoBackup.shared.statusJSON()
                view?.evaluateJavaScript("window.__omnicoreBackupStatus = JSON.stringify(\(status));", completionHandler: nil)
            }
        }

        func stopStatusUpdates() {
            statusTimer?.invalidate()
            statusTimer = nil
        }

        /// Ordres de la page Photos, acceptés seulement depuis OmniCore lui-même (cadre principal, même adresse).
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.host == home,
                  let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
            switch action {
            case "enable":
                PhotoBackup.shared.enable(token: body["token"] as? String ?? "", includeExisting: body["includeExisting"] as? Bool ?? true, wifiOnly: body["wifiOnly"] as? Bool ?? true)
            case "now":
                PhotoBackup.shared.runSoon()
            case "disable":
                PhotoBackup.shared.disable()
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url,
                  navigationAction.targetFrame?.isMainFrame != false,
                  let scheme = target.scheme, scheme == "http" || scheme == "https",
                  target.host != home
            else {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(target)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            onFailure("Impossible de joindre OmniCore. À la maison, vérifie que l’iPhone et le PC sont sur le même Wi-Fi. Dehors, active l’app Tailscale.")
        }
    }
}
