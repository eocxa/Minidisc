import SwiftUI
import WebKit
import OSLog
import SwiftSonic

enum AMLLLyricsPayload: Equatable {
    case ttml(NowLocalLyricsResponse)
    case structured(StructuredLyrics)

    static func == (lhs: AMLLLyricsPayload, rhs: AMLLLyricsPayload) -> Bool {
        switch (lhs, rhs) {
        case (.ttml(let a), .ttml(let b)):
            return a == b
        case (.structured(let a), .structured(let b)):
            return a == b
        default:
            return false
        }
    }
}

struct AMLLLyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    let payload: AMLLLyricsPayload
    var areControlsHidden: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !viewModel.isPlaying)) { timeline in
            let currentTimeSec = viewModel.interpolatedPosition(at: timeline.date)
            AMLLWebViewRepresentable(
                currentTimeMs: Int(currentTimeSec * 1000),
                isPlaying: viewModel.isPlaying,
                payload: payload,
                onSeek: { seconds in
                    viewModel.userTapped(seconds: seconds)
                }
            )
        }
    }
}

private struct AMLLWebViewRepresentable: UIViewRepresentable {
    let currentTimeMs: Int
    let isPlaying: Bool
    let payload: AMLLLyricsPayload
    let onSeek: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSeek: onSeek)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "onSeek")
        userContentController.add(context.coordinator, name: "onReady")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.targetWebView = webView

        // Cargar amll-engine.html desde los recursos locales
        if let url = Bundle.main.url(forResource: "amll-engine", withExtension: "html", subdirectory: "AMLL") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let url = Bundle.main.url(forResource: "amll-engine", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            // Fallback por si la estructura de carpetas de Xcode aplana los recursos
            let fm = FileManager.default
            if let bundlePath = Bundle.main.resourcePath {
                let candidates = [
                    "\(bundlePath)/AMLL/amll-engine.html",
                    "\(bundlePath)/amll-engine.html",
                    "\(bundlePath)/Resources/AMLL/amll-engine.html"
                ]
                for candidate in candidates {
                    if fm.fileExists(atPath: candidate) {
                        let candidateURL = URL(fileURLWithPath: candidate)
                        webView.loadFileURL(candidateURL, allowingReadAccessTo: candidateURL.deletingLastPathComponent())
                        break
                    }
                }
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(
            webView: uiView,
            currentTimeMs: currentTimeMs,
            isPlaying: isPlaying,
            payload: payload
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let onSeek: (Double) -> Void
        weak var targetWebView: WKWebView?
        private var isEngineReady = false
        private var lastLoadedPayload: AMLLLyricsPayload?
        private var lastPushedTimeMs: Int = -1
        private var lastPushedIsPlaying: Bool?
        private let logger = Logger(subsystem: "app.minidisc.amll", category: "Engine")

        init(onSeek: @escaping (Double) -> Void) {
            self.onSeek = onSeek
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isEngineReady = true
            applyCurrentPayload(to: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "onReady" {
                isEngineReady = true
                if let wv = targetWebView {
                    applyCurrentPayload(to: wv)
                }
            } else if message.name == "onSeek" {
                if let seconds = message.body as? Double {
                    onSeek(seconds)
                } else if let dict = message.body as? [String: Any], let time = dict["time"] as? Double {
                    onSeek(time)
                }
            }
        }

        func update(
            webView: WKWebView,
            currentTimeMs: Int,
            isPlaying: Bool,
            payload: AMLLLyricsPayload
        ) {
            if lastLoadedPayload != payload {
                lastLoadedPayload = payload
                if isEngineReady {
                    applyCurrentPayload(to: webView)
                }
            }

            guard isEngineReady else { return }

            let timeDiff = abs(currentTimeMs - lastPushedTimeMs)
            let isPlayingChanged = lastPushedIsPlaying != isPlaying

            // Actualizar si hay salto de tiempo > 300ms, si cambió el estado de reproducción, o periódicamente
            if timeDiff >= 120 || isPlayingChanged {
                let forceSeek = timeDiff >= 1000
                lastPushedTimeMs = currentTimeMs
                lastPushedIsPlaying = isPlaying
                let js = "window.amllSetTime(\(currentTimeMs), \(isPlaying ? "true" : "false"), \(forceSeek ? "true" : "false"));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        private func applyCurrentPayload(to webView: WKWebView) {
            guard let payload = lastLoadedPayload else { return }

            switch payload {
            case .ttml(let ttml):
                // 1. Si tenemos el TTML original sin procesar, es la máxima prioridad
                if let rawTTML = ttml.rawTTML, !rawTTML.isEmpty {
                    sendRawLyrics(to: webView, content: rawTTML, format: "ttml")
                    return
                }
                // 2. Si tenemos el LRC original
                if let rawLRC = ttml.rawLRC, !rawLRC.isEmpty {
                    sendRawLyrics(to: webView, content: rawLRC, format: "lrc")
                    return
                }
                // 3. Fallback: enviar la estructura codificada en JSON
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(ttml)
                    if let jsonStr = String(data: data, encoding: .utf8) {
                        let escaped = jsonStr
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "`", with: "\\`")
                            .replacingOccurrences(of: "$", with: "\\$")
                        let js = "window.amllLoadLyrics(`\(escaped)`, 'nowlocal');"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                } catch {
                    logger.error("Error codificando NowLocalLyricsResponse: \(error.localizedDescription)")
                }

            case .structured(let structured):
                // Enviar la lista de versos estructurados
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(structured.line)
                    if let jsonStr = String(data: data, encoding: .utf8) {
                        let escaped = jsonStr
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "`", with: "\\`")
                            .replacingOccurrences(of: "$", with: "\\$")
                        let js = "window.amllLoadLyrics(`\(escaped)`, 'structured');"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                } catch {
                    logger.error("Error codificando StructuredLyrics: \(error.localizedDescription)")
                }
            }
        }

        private func sendRawLyrics(to webView: WKWebView, content: String, format: String) {
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let js = "window.amllLoadLyrics(`\(escaped)`, '\(format)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
