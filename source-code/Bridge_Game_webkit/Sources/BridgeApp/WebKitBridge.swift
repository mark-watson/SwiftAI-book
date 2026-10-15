// WebKitBridge.swift -- Cocoa + WKWebView native macOS bridge.

import Cocoa
import WebKit
import BridgeEngine

public class BridgeScriptHandler: NSObject, WKScriptMessageHandler {
    private let service: BridgeEngineService
    weak var webView: WKWebView?

    public init(service: BridgeEngineService) {
        self.service = service
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "wkr_bridge" || message.name == "swift_bridge" else { return }
        guard let body = message.body as? [String: Any] else { return }

        let command = body["command"] as? String ?? ""
        let callbackId = body["callbackId"] as? String ?? "0"
        let payloadString: String
        if let s = body["payload"] as? String {
            payloadString = s
        } else if let dict = body["payload"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: data, encoding: .utf8) {
            payloadString = str
        } else {
            payloadString = "{}"
        }

        let responseJSON = service.handleCommandJSON(command: command, payloadJSON: payloadString)

        let escapedCallbackId = callbackId.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.webkit_racket._resolveCallback('\(escapedCallbackId)', \(responseJSON));"

        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

public class BridgeWindowController: NSWindowController, NSWindowDelegate {
    private var webView: WKWebView!
    private let service = BridgeEngineService()
    private var scriptHandler: BridgeScriptHandler!

    public convenience init() {
        let width: CGFloat = 1320
        let height: CGFloat = 960
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rubber Bridge — Swift WebKit"
        window.minSize = NSSize(width: 900, height: 700)
        window.center()

        self.init(window: window)
        window.delegate = self
        setupWebView(window: window)
    }

    private func setupWebView(window: NSWindow) {
        let contentController = WKUserContentController()
        scriptHandler = BridgeScriptHandler(service: service)
        contentController.add(scriptHandler, name: "wkr_bridge")
        contentController.add(scriptHandler, name: "swift_bridge")

        // Inject JS bridge helper matching index.html
        let bridgeJS = """
        window.webkit_racket = {
            _callbackId: 0,
            _callbacks: {},
            invoke: function(command, payload) {
                return new Promise(function(resolve, reject) {
                    var id = String(++window.webkit_racket._callbackId);
                    window.webkit_racket._callbacks[id] = { resolve: resolve, reject: reject };
                    var msg = {
                        command: command,
                        payload: JSON.stringify(payload || {}),
                        callbackId: id
                    };
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wkr_bridge) {
                        window.webkit.messageHandlers.wkr_bridge.postMessage(msg);
                    } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.swift_bridge) {
                        window.webkit.messageHandlers.swift_bridge.postMessage(msg);
                    } else {
                        reject(new Error("Native WebKit bridge message handler not available"));
                    }
                });
            },
            _resolveCallback: function(callbackId, result) {
                var cb = window.webkit_racket._callbacks[callbackId];
                if (cb) {
                    delete window.webkit_racket._callbacks[callbackId];
                    cb.resolve(result);
                }
            },
            _rejectCallback: function(callbackId, error) {
                var cb = window.webkit_racket._callbacks[callbackId];
                if (cb) {
                    delete window.webkit_racket._callbacks[callbackId];
                    cb.reject(error);
                }
            }
        };
        window.webkit_swift = window.webkit_racket;
        """

        let userScript = WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        scriptHandler.webView = webView

        window.contentView?.addSubview(webView)
        loadIndexHTML()
    }

    private func loadIndexHTML() {
        // 1. Try current working directory (useful during UI development)
        let localURL = URL(fileURLWithPath: "index.html")
        if FileManager.default.fileExists(atPath: localURL.path) {
            webView.loadFileURL(localURL, allowingReadAccessTo: localURL.deletingLastPathComponent())
            return
        }

        // 2. Try relative to executable
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let exeRelativeURL = exeDir.appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: exeRelativeURL.path) {
            webView.loadFileURL(exeRelativeURL, allowingReadAccessTo: exeDir)
            return
        }

        // 3. Fall back to embedded HTML (100% self-contained single binary)
        webView.loadHTMLString(EmbeddedAssets.indexHTML, baseURL: nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: BridgeWindowController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = BridgeWindowController()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
