import SwiftUI
import Combine
import WebKit

nonisolated enum CameraAccessError: Error {
    case invalidCode
    case unavailable
}

extension APIService {
    /// Exchanges the 4-digit access code for the live camera stream URL,
    /// the same way the website's Live Camera page does. The Worker keeps
    /// the current stream address, so the app never hard-codes it.
    func fetchCameraStreamURL(code: String, completion: @escaping (Result<URL, CameraAccessError>) -> Void) {
        guard let url = URL(string: "https://embersensor.com/api/camera-access") else {
            completion(.failure(.unavailable))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.httpBody = try? JSONEncoder().encode(["code": code])

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(.unavailable))
                return
            }
            if http.statusCode == 401 {
                completion(.failure(.invalidCode))
                return
            }
            guard http.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(CameraAccessResponse.self, from: data),
                  let streamURL = URL(string: decoded.url) else {
                completion(.failure(.unavailable))
                return
            }
            completion(.success(streamURL))
        }.resume()
    }
}

nonisolated private struct CameraAccessResponse: Decodable {
    let url: String
}

struct LiveFeedView: View {
    let api: APIService

    // Same 15-minute session as the website's Live Camera page.
    private let sessionLength: TimeInterval = 15 * 60

    @State private var code = ""
    @State private var streamURL: URL?
    @State private var unlockedAt: Date?
    @State private var isChecking = false
    @State private var message: String?
    @State private var sessionEnded = false
    @FocusState private var codeFieldFocused: Bool

    private let sessionTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let url = streamURL {
                StreamWebView(url: url)
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Lock") { lock(expired: false) }
                        }
                    }
            } else {
                codeEntry
            }
        }
        .onReceive(sessionTimer) { _ in
            if let start = unlockedAt, Date().timeIntervalSince(start) > sessionLength {
                lock(expired: true)
            }
        }
    }

    private var codeEntry: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "video.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                    .padding(.top, 40)

                Text(sessionEnded ? "Session ended" : "Live Camera")
                    .font(.title2)
                    .bold()

                Text(sessionEnded
                     ? "For safety, the live feed locks after 15 minutes. Enter your code to continue."
                     : "Enter your 4-digit access code to watch the live camera.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                SecureField("4-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .padding()
                    .frame(maxWidth: 220)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .focused($codeFieldFocused)
                    .onChange(of: code) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(4))
                        if digits != newValue { code = digits }
                    }

                Button(action: unlock) {
                    HStack {
                        if isChecking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isChecking ? "Checking..." : "Open Live Camera")
                    }
                    .bold()
                    .frame(maxWidth: 220)
                    .padding()
                    .background(code.count == 4 ? Color.orange : Color.orange.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(code.count != 4 || isChecking)

                if let message = message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func unlock() {
        guard code.count == 4, !isChecking else { return }
        isChecking = true
        message = nil
        codeFieldFocused = false

        api.fetchCameraStreamURL(code: code) { result in
            DispatchQueue.main.async {
                self.isChecking = false
                switch result {
                case .success(let url):
                    self.streamURL = url
                    self.unlockedAt = Date()
                    self.sessionEnded = false
                    self.code = ""
                case .failure(.invalidCode):
                    self.message = "That code didn't work. Please try again."
                    self.code = ""
                case .failure(.unavailable):
                    self.message = "Couldn't reach the live camera. Check your connection and try again."
                }
            }
        }
    }

    private func lock(expired: Bool) {
        streamURL = nil
        unlockedAt = nil
        sessionEnded = expired
        message = nil
    }
}

/// Web view for the camera's stream page. Inline playback and autoplay
/// are enabled so the video plays inside the tab instead of jumping to
/// the full-screen player.
private struct StreamWebView: UIViewRepresentable {
    let url: URL

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
