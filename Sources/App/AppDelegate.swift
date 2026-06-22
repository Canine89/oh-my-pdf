import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: DocumentWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        _ = UpdaterController.shared
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func showMainWindow() {
        if windowController == nil {
            windowController = DocumentWindowController()
        }
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: Brand.name)
        appMenu.addItem(withTitle: "\(Brand.name) 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "업데이트 확인...", action: #selector(UpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "\(Brand.name) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "파일")
        fileMenu.addItem(withTitle: "열기...", action: #selector(DocumentWindowController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "저장", action: #selector(DocumentWindowController.saveDocument(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "다른 이름으로 저장...", action: #selector(DocumentWindowController.saveDocumentAs(_:)), keyEquivalent: "S")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
