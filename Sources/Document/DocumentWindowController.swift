import AppKit
import PDFKit

final class DocumentWindowController: NSWindowController {
    private let pdfView = PDFView()
    private let statusLabel = NSTextField(labelWithString: "PDF를 열어 주세요.")
    private let pageLabel = NSTextField(labelWithString: "0 / 0")
    private let resultView = NSTextView()
    private let apiKeyField = NSSecureTextField()
    private let glossaryLabel = NSTextField(labelWithString: "용어집 없음")
    private let strengthPopup = NSPopUpButton()
    private let gptCheckbox = NSButton(checkboxWithTitle: "GPT 사용", target: nil, action: nil)
    private let publisherCheckbox = NSButton(checkboxWithTitle: "CSV 용어집", target: nil, action: nil)
    private let auxiliaryCheckbox = NSButton(checkboxWithTitle: "보조용언 붙임", target: nil, action: nil)

    private var documentURL: URL?
    private var glossaryRules: [GlossaryRule] = []
    private let correctionEngine = CorrectionEngine()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = Brand.name
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let toolbar = makeToolbar()
        let statusBar = makeStatusBar()
        let body = NSView()
        let sidePanel = makeSidePanel()
        let divider = NSBox()
        divider.boxType = .separator

        pdfView.autoScales = true
        pdfView.displayBox = .cropBox
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)

        [toolbar, body, statusBar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        [pdfView, divider, sidePanel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),

            body.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            body.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            body.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            sidePanel.topAnchor.constraint(equalTo: body.topAnchor),
            sidePanel.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            sidePanel.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            sidePanel.widthAnchor.constraint(equalToConstant: 340),

            divider.topAnchor.constraint(equalTo: body.topAnchor),
            divider.trailingAnchor.constraint(equalTo: sidePanel.leadingAnchor),
            divider.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            pdfView.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            pdfView.topAnchor.constraint(equalTo: body.topAnchor),
            pdfView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: body.bottomAnchor),

            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])
        updateControls()
    }

    private func makeToolbar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        bar.translatesAutoresizingMaskIntoConstraints = false

        addButton("열기", action: #selector(openDocument(_:)), to: bar)
        addButton("저장", action: #selector(saveDocument(_:)), to: bar)
        addButton("다른 이름", action: #selector(saveDocumentAs(_:)), to: bar)
        addSeparator(to: bar)
        addButton("이전", action: #selector(previousPage(_:)), to: bar)
        addButton("다음", action: #selector(nextPage(_:)), to: bar)
        bar.addArrangedSubview(pageLabel)
        addSeparator(to: bar)
        addButton("하이라이트", action: #selector(addHighlight(_:)), to: bar)
        addButton("밑줄", action: #selector(addUnderline(_:)), to: bar)
        addButton("취소선", action: #selector(addStrikeout(_:)), to: bar)
        addButton("텍스트 박스", action: #selector(addTextBox(_:)), to: bar)
        addButton("화살표 메모", action: #selector(addArrowTextBox(_:)), to: bar)
        addButton("선택 메모", action: #selector(addSelectedTextNote(_:)), to: bar)
        addButton("삭제 제안", action: #selector(addDeletionSuggestion(_:)), to: bar)
        addButton("대체 제안", action: #selector(addReplacementSuggestion(_:)), to: bar)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(spacer)

        let scan = NSButton(title: "맞춤법 검사", target: self, action: #selector(runCorrection(_:)))
        scan.bezelStyle = .rounded
        scan.keyEquivalent = "\r"
        bar.addArrangedSubview(scan)

        return bar
    }

    private func makeSidePanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical
        panel.spacing = 10
        panel.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        panel.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "AI 교정")
        title.font = .boldSystemFont(ofSize: 15)
        panel.addArrangedSubview(title)

        apiKeyField.placeholderString = "OpenAI API 키"
        apiKeyField.stringValue = KeychainStore.loadAPIKey() ?? ""
        apiKeyField.target = self
        apiKeyField.action = #selector(saveAPIKey(_:))
        panel.addArrangedSubview(apiKeyField)

        let saveKey = NSButton(title: "API 키 저장", target: self, action: #selector(saveAPIKey(_:)))
        saveKey.bezelStyle = .rounded
        panel.addArrangedSubview(saveKey)

        gptCheckbox.state = Settings.shared.useGPT ? .on : .off
        gptCheckbox.target = self
        gptCheckbox.action = #selector(updateSettings(_:))
        publisherCheckbox.state = Settings.shared.usePublisherRules ? .on : .off
        publisherCheckbox.target = self
        publisherCheckbox.action = #selector(updateSettings(_:))
        auxiliaryCheckbox.state = Settings.shared.joinAuxiliaryVerbs ? .on : .off
        auxiliaryCheckbox.target = self
        auxiliaryCheckbox.action = #selector(updateSettings(_:))
        panel.addArrangedSubview(gptCheckbox)
        panel.addArrangedSubview(publisherCheckbox)
        panel.addArrangedSubview(auxiliaryCheckbox)

        strengthPopup.removeAllItems()
        CorrectionStrength.allCases.forEach { strengthPopup.addItem(withTitle: $0.label) }
        strengthPopup.selectItem(at: CorrectionStrength.allCases.firstIndex(of: Settings.shared.correctionStrength) ?? 3)
        strengthPopup.target = self
        strengthPopup.action = #selector(updateSettings(_:))
        panel.addArrangedSubview(strengthPopup)

        let glossaryButton = NSButton(title: "CSV 용어집 불러오기", target: self, action: #selector(loadGlossary(_:)))
        glossaryButton.bezelStyle = .rounded
        panel.addArrangedSubview(glossaryButton)
        panel.addArrangedSubview(glossaryLabel)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        resultView.isEditable = false
        resultView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultView.string = "검사 결과가 여기에 표시됩니다."
        scroll.documentView = resultView
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        panel.addArrangedSubview(scroll)

        return panel
    }

    private func makeStatusBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        bar.addArrangedSubview(statusLabel)
        return bar
    }

    private func addButton(_ title: String, action: Selector, to stack: NSStackView) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        stack.addArrangedSubview(button)
    }

    private func addSeparator(to stack: NSStackView) {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(separator)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    private func open(url: URL) {
        guard let document = PDFDocument(url: url) else {
            showAlert("PDF를 열 수 없습니다.")
            return
        }
        documentURL = url
        pdfView.document = document
        if let firstPage = document.page(at: 0) {
            pdfView.go(to: firstPage)
        }
        pdfView.autoScales = true
        pdfView.layoutDocumentView()
        DispatchQueue.main.async { [weak self] in
            self?.pdfView.autoScales = true
            self?.pdfView.scaleFactor = self?.pdfView.scaleFactorForSizeToFit ?? 1
            self?.pdfView.layoutDocumentView()
            self?.updateControls()
        }
        window?.title = "\(Brand.name) - \(url.lastPathComponent)"
        statusLabel.stringValue = "열림: \(url.path)"
        updateControls()
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let url = documentURL else {
            saveDocumentAs(sender)
            return
        }
        guard pdfView.document?.write(to: url) == true else {
            showAlert("PDF 저장에 실패했습니다.")
            return
        }
        statusLabel.stringValue = "저장됨: \(url.path)"
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let document = pdfView.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "corrected.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard document.write(to: url) else {
            showAlert("PDF 저장에 실패했습니다.")
            return
        }
        documentURL = url
        statusLabel.stringValue = "저장됨: \(url.path)"
    }

    @objc private func previousPage(_ sender: Any?) {
        pdfView.goToPreviousPage(sender)
        updateControls()
    }

    @objc private func nextPage(_ sender: Any?) {
        pdfView.goToNextPage(sender)
        updateControls()
    }

    @objc private func addHighlight(_ sender: Any?) {
        addMarkupAnnotation(.highlight, color: Brand.highlight)
    }

    @objc private func addUnderline(_ sender: Any?) {
        addMarkupAnnotation(.underline, color: .systemBlue)
    }

    @objc private func addStrikeout(_ sender: Any?) {
        addMarkupAnnotation(.strikeOut, color: .systemRed)
    }

    @objc private func addTextBox(_ sender: Any?) {
        guard let page = pdfView.currentPage else { return }
        let annotation = PDFAnnotation(bounds: centeredBounds(on: page), forType: .freeText, withProperties: nil)
        annotation.contents = "메모"
        annotation.font = .systemFont(ofSize: 13)
        annotation.color = .clear
        annotation.fontColor = .labelColor
        annotation.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.24)
        page.addAnnotation(annotation)
    }

    @objc private func addArrowTextBox(_ sender: Any?) {
        guard let page = pdfView.currentPage else { return }
        let bounds = centeredBounds(on: page)
        let line = PDFAnnotation(bounds: bounds.insetBy(dx: -70, dy: -30), forType: .line, withProperties: nil)
        line.color = Brand.accent
        line.border = PDFBorder()
        line.border?.lineWidth = 2
        line.startPoint = NSPoint(x: line.bounds.minX, y: line.bounds.minY)
        line.endPoint = NSPoint(x: line.bounds.midX, y: line.bounds.midY)
        line.endLineStyle = .closedArrow
        page.addAnnotation(line)

        let text = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        text.contents = "대체/설명 입력"
        text.font = .systemFont(ofSize: 13)
        text.color = .clear
        text.fontColor = .labelColor
        text.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12)
        page.addAnnotation(text)
    }

    @objc private func addSelectedTextNote(_ sender: Any?) {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first else { return }
        let note = PDFAnnotation(bounds: selection.bounds(for: page).offsetBy(dx: 12, dy: 12),
                                 forType: .text,
                                 withProperties: nil)
        note.contents = "선택 텍스트 주석: \(selection.string ?? "")"
        note.color = .systemYellow
        page.addAnnotation(note)
    }

    @objc private func addDeletionSuggestion(_ sender: Any?) {
        guard let selection = pdfView.currentSelection else { return }
        addMarkupAnnotation(.strikeOut, color: .systemRed)
        if let page = selection.pages.first {
            let note = PDFAnnotation(bounds: selection.bounds(for: page).offsetBy(dx: 12, dy: 12),
                                     forType: .text,
                                     withProperties: nil)
            note.contents = "삭제 제안: \(selection.string ?? "")"
            note.color = .systemRed
            page.addAnnotation(note)
        }
    }

    @objc private func addReplacementSuggestion(_ sender: Any?) {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first else { return }
        addMarkupAnnotation(.strikeOut, color: .systemRed)
        let replacement = prompt("대체 텍스트", message: "선택한 텍스트를 무엇으로 바꿀까요?")
        guard !replacement.isEmpty else { return }
        let bounds = selection.bounds(for: page).offsetBy(dx: 12, dy: 18)
        let annotation = PDFAnnotation(bounds: NSRect(x: bounds.minX, y: bounds.minY, width: max(bounds.width, 180), height: 42),
                                       forType: .freeText,
                                       withProperties: nil)
        annotation.contents = replacement
        annotation.font = .systemFont(ofSize: 12)
        annotation.fontColor = .systemRed
        annotation.color = .clear
        annotation.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10)
        page.addAnnotation(annotation)
    }

    private func addMarkupAnnotation(_ type: PDFAnnotationSubtype, color: NSColor) {
        guard let selection = pdfView.currentSelection else { return }
        let selections = selection.selectionsByLine()
        let targets = selections.isEmpty ? [selection] : selections
        for item in targets {
            for page in item.pages {
                let bounds = item.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                page.addAnnotation(annotation)
            }
        }
    }

    @objc private func loadGlossary(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            glossaryRules = try Glossary.loadCSV(from: url)
            glossaryLabel.stringValue = "\(url.lastPathComponent) - \(glossaryRules.count)개 규칙"
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    @objc private func saveAPIKey(_ sender: Any?) {
        do {
            try KeychainStore.saveAPIKey(apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            statusLabel.stringValue = "API 키가 Keychain에 저장되었습니다."
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    @objc private func updateSettings(_ sender: Any?) {
        Settings.shared.useGPT = gptCheckbox.state == .on
        Settings.shared.usePublisherRules = publisherCheckbox.state == .on
        Settings.shared.joinAuxiliaryVerbs = auxiliaryCheckbox.state == .on
        let index = max(0, strengthPopup.indexOfSelectedItem)
        Settings.shared.correctionStrength = CorrectionStrength.allCases[index]
    }

    @objc private func runCorrection(_ sender: Any?) {
        guard let document = pdfView.document else { return }
        updateSettings(nil)
        resultView.string = ""
        statusLabel.stringValue = "맞춤법 검사 중..."

        let options = CorrectionOptions(useGPT: Settings.shared.useGPT,
                                        correctionStrength: Settings.shared.correctionStrength,
                                        usePublisherRules: Settings.shared.usePublisherRules,
                                        joinAuxiliaryVerbs: Settings.shared.joinAuxiliaryVerbs)

        Task {
            var results: [PageCorrectionResult] = []
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                let raw = page.string ?? ""
                let normalized = PDFTextNormalizer.normalizePageText(raw)
                do {
                    let corrected = try await correctionEngine.correct(text: normalized, options: options, glossary: glossaryRules)
                    let pageResult = PageCorrectionResult(pageIndex: pageIndex,
                                                          originalText: raw,
                                                          normalizedText: normalized,
                                                          correctedText: corrected.corrected,
                                                          corrections: corrected.corrections)
                    results.append(pageResult)
                    applyCorrections(pageResult, in: document)
                    appendResult(pageResult)
                } catch {
                    appendLog("\(pageIndex + 1)쪽 실패: \(error.localizedDescription)")
                }
                statusLabel.stringValue = "맞춤법 검사 중... \(pageIndex + 1) / \(document.pageCount)"
            }
            let count = results.reduce(0) { $0 + $1.corrections.count }
            statusLabel.stringValue = "검사 완료: \(count)개 교정 후보"
        }
    }

    private func applyCorrections(_ result: PageCorrectionResult, in document: PDFDocument) {
        guard document.page(at: result.pageIndex) != nil else { return }
        for correction in result.corrections {
            let selections = document.findString(correction.original, withOptions: [.caseInsensitive])
                .filter { $0.pages.contains { document.index(for: $0) == result.pageIndex } }
            for selection in selections {
                for page in selection.pages where document.index(for: page) == result.pageIndex {
                    let bounds = selection.bounds(for: page)
                    let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    highlight.color = Brand.correction
                    highlight.contents = "\(correction.original) -> \(correction.corrected)\n\(correction.explanation)"
                    page.addAnnotation(highlight)

                    let note = PDFAnnotation(bounds: bounds.offsetBy(dx: 8, dy: 8), forType: .text, withProperties: nil)
                    note.contents = "\(correction.corrected)\n\(correction.explanation)"
                    note.color = .systemRed
                    page.addAnnotation(note)
                }
            }
        }
    }

    private func appendResult(_ result: PageCorrectionResult) {
        guard result.hasErrors else { return }
        appendLog("\n[\(result.pageIndex + 1)쪽]")
        for item in result.corrections {
            appendLog("- \(item.original) -> \(item.corrected) (\(item.type)): \(item.explanation)")
        }
    }

    private func appendLog(_ text: String) {
        resultView.string += resultView.string.isEmpty ? text : "\n\(text)"
        resultView.scrollToEndOfDocument(nil)
    }

    private func centeredBounds(on page: PDFPage) -> NSRect {
        let pageBounds = page.bounds(for: .mediaBox)
        return NSRect(x: pageBounds.midX - 90, y: pageBounds.midY - 24, width: 180, height: 48)
    }

    private func updateControls() {
        guard let document = pdfView.document else {
            pageLabel.stringValue = "0 / 0"
            return
        }
        let current = pdfView.currentPage.map { document.index(for: $0) + 1 } ?? 1
        pageLabel.stringValue = "\(current) / \(document.pageCount)"
    }

    private func prompt(_ title: String, message: String) -> String {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn ? input.stringValue : ""
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
