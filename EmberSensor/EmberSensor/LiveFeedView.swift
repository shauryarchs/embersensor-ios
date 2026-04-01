import SwiftUI
import WebKit

struct LiveFeedView: UIViewRepresentable {
    let url = URL(string: "https://livecam.embersensor.com/reolink")!

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
