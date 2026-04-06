import SwiftUI
import WebKit

struct FireGraphView: UIViewRepresentable {
    let url = URL(string: "https://embersensor.com/fire-graph.html")!

    private var mobileFixScript: String {
        """
        // Inject viewport meta tag if missing
        if (!document.querySelector('meta[name="viewport"]')) {
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes';
            document.head.appendChild(meta);
        }

        // Inject mobile-friendly CSS overrides
        var style = document.createElement('style');
        style.textContent = `
            #site-header, #site-footer { display: none !important; }
            .graph-page { padding: 12px 0 24px !important; }
            .graph-wrap { width: 100% !important; padding: 0 8px !important; box-sizing: border-box !important; }
            #fire-graph { height: 50vh !important; min-height: 300px !important; position: relative !important; }
            .filter-panel { padding: 10px 12px !important; }
            .filter-row { flex-direction: column !important; gap: 8px !important; }
            .filter-group { min-width: 100% !important; }
            .qq-grid { grid-template-columns: 1fr !important; gap: 6px !important; }
            .qq-grid .qq-item { font-size: 12px !important; padding: 8px 10px !important; }
            .nl-input-wrap { flex-direction: column !important; }
            .layout-row, .label-toggle-row {
                position: static !important;
                top: auto !important; left: auto !important;
                transform: none !important;
                display: flex !important; justify-content: center !important;
                margin: 6px auto !important; flex-wrap: wrap !important; gap: 4px !important;
                z-index: 10 !important;
            }
            .layout-row button, .label-toggle-row label { font-size: 11px !important; padding: 4px 8px !important; }
            .graph-legend { font-size: 12px !important; flex-wrap: wrap !important; }
            .graph-summary { font-size: 13px !important; }
            .container { max-width: 100% !important; padding: 0 8px !important; }
            .filter-tabs button { font-size: 12px !important; padding: 6px 10px !important; }

            /* Landscape: use horizontal space better */
            @media (orientation: landscape) {
                .qq-grid { grid-template-columns: 1fr 1fr !important; }
                .filter-row { flex-direction: row !important; flex-wrap: wrap !important; }
                .filter-group { min-width: 45% !important; flex: 1 1 45% !important; }
                #fire-graph { height: 60vh !important; }
                .layout-row, .label-toggle-row { margin: 4px auto !important; }
            }
        `;
        document.head.appendChild(style);

        // Move layout/label rows outside the graph so they don't overlap
        var graph = document.getElementById('fire-graph');
        if (graph) {
            var layoutRow = graph.querySelector('.layout-row');
            var labelRow = graph.querySelector('.label-toggle-row');
            if (layoutRow) graph.parentNode.insertBefore(layoutRow, graph);
            if (labelRow) graph.parentNode.insertBefore(labelRow, graph);
        }
        """
    }

    func makeUIView(context: Context) -> WKWebView {
        let userScript = WKUserScript(
            source: mobileFixScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        let contentController = WKUserContentController()
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
