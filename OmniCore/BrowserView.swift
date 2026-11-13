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
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let home: String?
        private let onFailure: @MainActor (String) -> Void

        init(home: String?, onFailure: @escaping @MainActor (String) -> Void) {
            self.home = home
            self.onFailure = onFailure
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
