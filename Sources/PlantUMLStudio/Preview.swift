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
    if document.focusRequest == "diagram" {
      web.window?.makeFirstResponder(web)
      DispatchQueue.main.async { document.focusRequest = "" }
    }
    if context.coordinator.returnRequest != document.previewReturn {
      context.coordinator.returnRequest = document.previewReturn
      context.coordinator.highlightSelection(web, scroll: true)
    }
    let html =
      "<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\"><style>body { background:#f5f5f7; padding:24px; margin:0 } svg { background:white; max-width:none; }</style></head><body>\(document.svg)</body></html>"
    if context.coordinator.last != html {
      context.coordinator.last = html
      web.evaluateJavaScript("[window.scrollX,window.scrollY]") { result, _ in
        if let offset = result as? [Double], offset.count == 2 {
          context.coordinator.scrollOffset = offset
        }
        web.loadHTMLString(html, baseURL: nil)
      }
    } else {
      context.coordinator.applyZoom(web)
      context.coordinator.highlightSelection(web, scroll: false)
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator(document) }
  @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var last = "", zoom = 1.0
    var scrollOffset = [0.0, 0.0]
    var returnRequest = 0
    var document: StudioDocument
    init(_ document: StudioDocument) { self.document = document }
    func userContentController(
      _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard let payload = message.body as? [String: String], let selected = element(payload) else {
        return
      }
      document.navigationRange = selected.range
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
        self.document.navigationRange = selected.range
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
      let expression =
        zoom > 0
        ? String(zoom)
        : zoom == -1
          ? "(innerWidth-48)/s.viewBox.baseVal.width"
          : "Math.min((innerWidth-48)/s.viewBox.baseVal.width,(innerHeight-48)/s.viewBox.baseVal.height)"
      web.evaluateJavaScript(
        "(() => { const s=document.querySelector('svg'); if(s) s.style.zoom=\(expression); })()",
        completionHandler: nil)
    }
    func highlightSelection(_ web: WKWebView, scroll: Bool) {
      guard document.parsed.source == document.source else { return }
      var identifier = ""
      var label = ""
      if let element = document.parsed.elements.first(where: { $0.id == document.selection }) {
        let ns = document.source as NSString
        if ["entity", "participant"].contains(element.kind),
          let range = element.fields["alias"] ?? element.fields["name"]
        {
          identifier = ns.substring(with: range).trimmingCharacters(
            in: CharacterSet(charactersIn: "\" "))
        }
        if let range = element.fields["label"] ?? element.fields["name"] {
          label = ns.substring(with: range).trimmingCharacters(
            in: CharacterSet(charactersIn: "\" "))
        }
      }
      if !identifier.isEmpty && element(["entity": identifier])?.id != document.selection {
        identifier = ""
      }
      if !label.isEmpty && element(["text": label])?.id != document.selection { label = "" }
      guard
        let data = try? JSONSerialization.data(withJSONObject: [
          "identifier": identifier, "label": label,
        ]), let payload = String(data: data, encoding: .utf8)
      else { return }
      let script = """
        (() => { document.querySelectorAll('[data-studio-selected]').forEach(n => {n.style.outline='';n.removeAttribute('data-studio-selected');});
        const p=\(payload); let matches=[];
        if(p.identifier) { matches=Array.from(document.querySelectorAll('[id]')).filter(n=>n.id==='elem_'+p.identifier); }
        if(!matches.length && p.label) matches=Array.from(document.querySelectorAll('text')).filter(n=>n.textContent.trim()===p.label);
        if(matches.length===1) { const n=matches[0]; n.setAttribute('data-studio-selected','true'); n.style.outline='2px solid #6b5cff'; if(\(scroll ? "true" : "false")) n.scrollIntoView({block:'center',inline:'center'}); } })()
        """
      web.evaluateJavaScript(script, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      applyZoom(webView)
      webView.evaluateJavaScript(
        "window.scrollTo(\(scrollOffset[0]),\(scrollOffset[1]))", completionHandler: nil)
      highlightSelection(webView, scroll: false)
    }
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
