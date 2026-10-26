import SwiftUI
import WebKit

struct LiveFeedView: UIViewRepresentable {
    // Defaults to the yard camera; the Auto Fire Suppression tab passes
    // the nozzle camera URL it gets from the Worker.
    var url = URL(string: "https://livecam.embersensor.com/yard-cam/")!

    // Inline playback and autoplay are enabled so the video plays inside
    // the tab instead of jumping to the full-screen player.
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
