import AppKit
import Sparkle

final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController?

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        if key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = "업데이트 키가 아직 설정되지 않았습니다."
            alert.informativeText = "Sparkle EdDSA 키를 만든 뒤 project.yml의 SUPublicEDKey를 채우면 자동 업데이트를 사용할 수 있습니다."
            alert.runModal()
            return
        }
        controller.checkForUpdates(sender)
    }
}
