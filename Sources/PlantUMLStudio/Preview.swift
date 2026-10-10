import AppKit
import ERModule
import PlantUMLCore
import Rendering
import SequenceModule
import SwiftUI
import WebKit

struct Preview: NSViewRepresentable {
  @ObservedObject var document: StudioDocument
  let zoom: Double
  func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.userContentController.add(context.coordinator, name: "selectElement")
    let script = """
      document.addEventListener('click', e => {
        const text=e.target.closest('text');
        const group=e.target.closest('[id^="elem_"]');
        window.webkit.messageHandlers.selectElement.postMessage({text:text?.textContent || '', entity:group?.id.substring(5) || ''});
      });
      let dragging=false, startX=0, startY=0, scrollX=0, scrollY=0;
      document.addEventListener('mousedown', e => {
        if(e.button === 1 || e.altKey) { dragging=true; startX=e.clientX; startY=e.clientY; scrollX=window.scrollX; scrollY=window.scrollY; e.preventDefault(); }
      });
      document.addEventListener('mousemove', e => { if(dragging) window.scrollTo(scrollX+startX-e.clientX,scrollY+startY-e.clientY); });
      document.addEventListener('mouseup', () => dragging=false);
      """
    config.userContentController.addUserScript(
      WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    let web = PreviewWebView(frame: .zero, configuration: config)
    web.navigationDelegate = context.coordinator
    web.contextAction = { event in context.coordinator.contextMenu(web, event: event) }
    return web
  }
  func updateNSView(_ web: WKWebView, context: Context) {
    context.coordinator.document = document
    context.coordinator.zoom = zoom
    let html =
      "<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\"><style>body { background:#f5f5f7; padding:24px; margin:0 } svg { background:white; max-width:none; }</style></head><body>\(document.svg)</body></html>"
    if context.coordinator.last != html {
      context.coordinator.last = html
      web.loadHTMLString(html, baseURL: nil)
    } else {
      context.coordinator.applyZoom(web)
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator(document) }
  @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var last = "", zoom = 1.0
    var document: StudioDocument
    init(_ document: StudioDocument) { self.document = document }
    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard let payload = message.body as? [String: String], let selected = element(payload) else {
        return
      }
      document.selection = selected.id
    }
    func element(_ payload: [String: String]) -> Element? {
      guard document.canEdit else { return nil }
      let ns = document.parsed.source as NSString
      let matches = document.parsed.elements.filter { element in
        for key in payload["entity"]?.isEmpty == false ? ["alias", "name"] : ["label", "name"] {
          guard let range = element.fields[key] else { continue }
          let value = ns.substring(with: range).trimmingCharacters(
            in: CharacterSet(charactersIn: "\" "))
          if value == (payload["entity"]?.isEmpty == false ? payload["entity"] : payload["text"]) {
            return true
          }
        }
        return false
      }
      return matches.count == 1 ? matches[0] : nil
    }
    func contextMenu(_ web: WKWebView, event: NSEvent) {
      let point = web.convert(event.locationInWindow, from: nil)
      let y = web.isFlipped ? point.y : web.bounds.height - point.y
      let script = """
        (() => {const node=document.elementFromPoint(\(point.x),\(y)); const text=node?.closest('text'); const group=node?.closest('[id^="elem_"]'); return {text:text?.textContent || '',entity:group?.id.substring(5) || ''};})()
        """
      web.evaluateJavaScript(script) { [weak self, weak web] result, error in
        guard let self, let web, let payload = result as? [String: String],
          let selected = self.element(payload)
        else { return }
        self.document.selection = selected.id
        let menu = NSMenu()
        let delete = NSMenuItem(
          title: "Удалить элемент", action: #selector(self.deleteSelected), keyEquivalent: "")
        delete.target = self
        delete.isEnabled = selected.kind != "unsupported" && selected.kind != "branch"
        menu.addItem(delete)
        NSMenu.popUpContextMenu(menu, with: event, for: web)
      }
    }
    @objc func deleteSelected() {
      guard let selected = document.parsed.elements.first(where: { $0.id == document.selection })
      else { return }
      document.edit { try ConstructorOperations.delete(selected, in: document.parsed) }
    }
    func applyZoom(_ web: WKWebView) {
      let script =
        zoom > 0
        ? "document.querySelector('svg').style.zoom='\(zoom)'"
        : "const s=document.querySelector('svg'); if(s) s.style.zoom=Math.min((innerWidth-48)/s.viewBox.baseVal.width,(innerHeight-48)/s.viewBox.baseVal.height)"
      web.evaluateJavaScript(script, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { applyZoom(webView) }
    func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) { decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel) }
  }
}

@MainActor private final class PreviewWebView: WKWebView {
  var contextAction: ((NSEvent) -> Void)?
  override func rightMouseDown(with event: NSEvent) { contextAction?(event) }
}
