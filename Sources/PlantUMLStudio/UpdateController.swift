import AppKit
import Combine
import Sparkle

/// Sparkle owns version comparison, authenticated download and installation.
@MainActor final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
  @Published private(set) var canCheck = false
  private var controller: SPUStandardUpdaterController?
  private var observation: AnyCancellable?
  private var pendingInstall: (() -> Void)?
  weak var applicationDelegate: ApplicationDelegate?

  override init() {
    super.init()
    let bundle = Bundle.main
    guard ProcessInfo.processInfo.environment["PLANTUML_STUDIO_SMOKE_DIR"] == nil,
      let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      let url = URL(string: feed), url.scheme == "https", url.host != nil,
      let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      Data(base64Encoded: key)?.count == 32
    else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    observation = controller.updater.publisher(for: \.canCheckForUpdates)
      .sink { [weak self] value in
        guard let self else { return }
        self.canCheck = value || self.pendingInstall != nil
      }
    controller.startUpdater()
    // Non-interactive startup check; network errors never block opening documents.
    if controller.updater.canCheckForUpdates {
      controller.updater.checkForUpdatesInBackground()
    }
  }

  func checkForUpdates() {
    if pendingInstall != nil { resumeInstallIfApproved() } else { controller?.checkForUpdates(nil) }
  }

  func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] }

  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    pendingInstall = installHandler
    canCheck = true
    DispatchQueue.main.async { [weak self] in self?.resumeInstallIfApproved() }
    return true
  }

  private func resumeInstallIfApproved() {
    guard let delegate = applicationDelegate, delegate.approveUnsavedDocuments(),
      let handler = pendingInstall
    else { return }
    delegate.workspace?.persist()
    pendingInstall = nil
    canCheck = false
    handler()
  }
}
