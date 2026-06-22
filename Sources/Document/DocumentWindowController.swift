import AppKit
import PDFKit

private enum AnnotationTool: CaseIterable {
    case select
    case highlight
    case underline
    case strikeout
    case textBox
    case arrowTextBox
    case selectedNote
    case deletion
    case replacement

    var title: String {
        switch self {
        case .select: return "선택"
        case .highlight: return "하이라이트"
        case .underline: return "밑줄"
        case .strikeout: return "취소선"
        case .textBox: return "텍스트 박스"
        case .arrowTextBox: return "화살표 메모"
        case .selectedNote: return "선택 메모"
        case .deletion: return "삭제 제안"
        case .replacement: return "대체 제안"
        }
    }
}

private struct AnnotationListItem {
    let pageIndex: Int
    let annotation: PDFAnnotation

    var pageText: String {
        "\(pageIndex + 1)"
    }

    var typeText: String {
        if annotation.contents?.hasPrefix("[AI]") == true { return "AI" }
        switch annotation.type {
        case "Highlight": return "하이라이트"
        case "Underline": return "밑줄"
        case "StrikeOut": return "취소선"
        case "FreeText": return "텍스트"
        case "Line": return "화살표"
        case "Text": return "메모"
        default: return annotation.type ?? "주석"
        }
    }

    var summary: String {
        let value = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "(내용 없음)" : value
    }
}

private enum UndoAction {
    case add([(PDFPage, PDFAnnotation)])
    case remove([(PDFPage, PDFAnnotation)])
}

private final class AnnotatingPDFView: PDFView {
    weak var annotationDelegate: AnnotatingPDFViewDelegate?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)

        if let page = page(for: viewPoint, nearest: true) {
            let pagePoint = convert(viewPoint, to: page)
            if let annotation = page.annotation(at: pagePoint) {
                annotationDelegate?.pdfView(self, didSelect: annotation, on: page)
                if event.clickCount >= 2 {
                    annotationDelegate?.pdfView(self, didRequestEdit: annotation, on: page)
                }
                return
            }
        }

        if annotationDelegate?.pdfView(self, didClickEmptyPageAt: viewPoint) == true {
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let command = event.modifierFlags.contains(.command)
        let control = event.modifierFlags.contains(.control)

        if key == "z", command || control {
            annotationDelegate?.pdfViewDidRequestUndo(self)
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            annotationDelegate?.pdfViewDidRequestDelete(self)
            return
        }
        if event.keyCode == 36 {
            annotationDelegate?.pdfViewDidRequestEditSelected(self)
            return
        }
        super.keyDown(with: event)
    }

    @objc func undo(_ sender: Any?) {
        annotationDelegate?.pdfViewDidRequestUndo(self)
    }

    @objc func delete(_ sender: Any?) {
        annotationDelegate?.pdfViewDidRequestDelete(self)
    }

    @objc func editSelectedAnnotation(_ sender: Any?) {
        annotationDelegate?.pdfViewDidRequestEditSelected(self)
    }
}

private protocol AnnotatingPDFViewDelegate: AnyObject {
    func pdfView(_ pdfView: AnnotatingPDFView, didSelect annotation: PDFAnnotation, on page: PDFPage)
    func pdfView(_ pdfView: AnnotatingPDFView, didRequestEdit annotation: PDFAnnotation, on page: PDFPage)
    func pdfView(_ pdfView: AnnotatingPDFView, didClickEmptyPageAt viewPoint: NSPoint) -> Bool
    func pdfViewDidRequestUndo(_ pdfView: AnnotatingPDFView)
    func pdfViewDidRequestDelete(_ pdfView: AnnotatingPDFView)
    func pdfViewDidRequestEditSelected(_ pdfView: AnnotatingPDFView)
}

final class DocumentWindowController: NSWindowController {
    private let pdfView = AnnotatingPDFView()
    private let statusLabel = NSTextField(labelWithString: "PDF를 열어 주세요.")
    private let pageLabel = NSTextField(labelWithString: "0 / 0")
    private let annotationTable = NSTableView()
    private let commentCountLabel = NSTextField(labelWithString: "0개")
    private let selectedCommentTitle = NSTextField(labelWithString: "선택한 주석 없음")
    private let selectedCommentEditor = NSTextView()
    private let apiKeyField = NSSecureTextField()
    private let glossaryLabel = NSTextField(labelWithString: "용어집 없음")
    private let strengthPopup = NSPopUpButton()
    private let gptCheckbox = NSButton(checkboxWithTitle: "GPT", target: nil, action: nil)
    private let publisherCheckbox = NSButton(checkboxWithTitle: "CSV", target: nil, action: nil)
    private let auxiliaryCheckbox = NSButton(checkboxWithTitle: "보조용언", target: nil, action: nil)

    private var documentURL: URL?
    private var glossaryRules: [GlossaryRule] = []
    private var annotationItems: [AnnotationListItem] = []
    private var selectedAnnotation: PDFAnnotation?
    private var selectedAnnotationPage: PDFPage?
    private var selectedTool: AnnotationTool = .select
    private var toolButtons: [AnnotationTool: NSButton] = [:]
    private var undoStack: [UndoAction] = []
    private let correctionEngine = CorrectionEngine()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
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
        let leftPanel = makeLeftPanel()
        let divider = NSBox()
        divider.boxType = .separator

        pdfView.annotationDelegate = self
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
        [leftPanel, divider, pdfView].forEach {
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

            leftPanel.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            leftPanel.topAnchor.constraint(equalTo: body.topAnchor),
            leftPanel.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            leftPanel.widthAnchor.constraint(equalToConstant: 300),

            divider.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            divider.topAnchor.constraint(equalTo: body.topAnchor),
            divider.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            pdfView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: body.topAnchor),
            pdfView.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: body.bottomAnchor),

            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 460)
        ])
        setTool(.select)
        updateControls()
    }

    private func makeToolbar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 7
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

        AnnotationTool.allCases.forEach { tool in
            let button = NSButton(title: tool.title, target: self, action: #selector(selectTool(_:)))
            button.bezelStyle = .texturedRounded
            button.setButtonType(.toggle)
            button.tag = AnnotationTool.allCases.firstIndex(of: tool) ?? 0
            toolButtons[tool] = button
            bar.addArrangedSubview(button)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(spacer)

        let scan = NSButton(title: "맞춤법 검사", target: self, action: #selector(runCorrection(_:)))
        scan.bezelStyle = .rounded
        scan.keyEquivalent = "\r"
        bar.addArrangedSubview(scan)

        return bar
    }

    private func makeLeftPanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical
        panel.spacing = 10
        panel.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let title = NSTextField(labelWithString: "주석 목록")
        title.font = .boldSystemFont(ofSize: 15)
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.addArrangedSubview(title)
        let titleSpacer = NSView()
        titleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(titleSpacer)
        commentCountLabel.textColor = .secondaryLabelColor
        commentCountLabel.font = .systemFont(ofSize: 12)
        titleRow.addArrangedSubview(commentCountLabel)
        panel.addArrangedSubview(titleRow)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        annotationTable.headerView = nil
        annotationTable.rowHeight = 64
        annotationTable.intercellSpacing = NSSize(width: 0, height: 6)
        annotationTable.selectionHighlightStyle = .none
        annotationTable.delegate = self
        annotationTable.dataSource = self
        annotationTable.target = self
        annotationTable.doubleAction = #selector(editSelectedAnnotation(_:))
        addTableColumn("comment", width: 276)
        scroll.documentView = annotationTable
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        panel.addArrangedSubview(scroll)

        selectedCommentTitle.font = .boldSystemFont(ofSize: 13)
        selectedCommentTitle.textColor = .secondaryLabelColor
        panel.addArrangedSubview(selectedCommentTitle)

        let noteScroll = NSScrollView()
        noteScroll.hasVerticalScroller = true
        noteScroll.borderType = .bezelBorder
        selectedCommentEditor.font = .systemFont(ofSize: 13)
        selectedCommentEditor.isEditable = true
        selectedCommentEditor.string = ""
        noteScroll.documentView = selectedCommentEditor
        noteScroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
        panel.addArrangedSubview(noteScroll)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        addButton("메모 저장", action: #selector(saveSelectedAnnotationNote(_:)), to: actionRow)
        addButton("삭제", action: #selector(deleteSelectedAnnotation(_:)), to: actionRow)
        panel.addArrangedSubview(actionRow)

        let aiTitle = NSTextField(labelWithString: "AI 설정")
        aiTitle.font = .boldSystemFont(ofSize: 15)
        panel.addArrangedSubview(aiTitle)

        apiKeyField.placeholderString = "OpenAI API 키"
        apiKeyField.stringValue = KeychainStore.loadAPIKey() ?? ""
        apiKeyField.target = self
        apiKeyField.action = #selector(saveAPIKey(_:))
        panel.addArrangedSubview(apiKeyField)

        let saveKey = NSButton(title: "API 키 저장", target: self, action: #selector(saveAPIKey(_:)))
        saveKey.bezelStyle = .rounded
        panel.addArrangedSubview(saveKey)

        let checkRow = NSStackView()
        checkRow.orientation = .horizontal
        checkRow.spacing = 8
        gptCheckbox.state = Settings.shared.useGPT ? .on : .off
        gptCheckbox.target = self
        gptCheckbox.action = #selector(updateSettings(_:))
        publisherCheckbox.state = Settings.shared.usePublisherRules ? .on : .off
        publisherCheckbox.target = self
        publisherCheckbox.action = #selector(updateSettings(_:))
        auxiliaryCheckbox.state = Settings.shared.joinAuxiliaryVerbs ? .on : .off
        auxiliaryCheckbox.target = self
        auxiliaryCheckbox.action = #selector(updateSettings(_:))
        checkRow.addArrangedSubview(gptCheckbox)
        checkRow.addArrangedSubview(publisherCheckbox)
        checkRow.addArrangedSubview(auxiliaryCheckbox)
        panel.addArrangedSubview(checkRow)

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

        return panel
    }

    private func addTableColumn(_ identifier: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.width = width
        column.resizingMask = .autoresizingMask
        annotationTable.addTableColumn(column)
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
        selectedAnnotation = nil
        selectedAnnotationPage = nil
        undoStack.removeAll()
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
            self?.refreshAnnotationList()
            self?.updateControls()
        }
        window?.title = "\(Brand.name) - \(url.lastPathComponent)"
        statusLabel.stringValue = "열림: \(url.path)"
        refreshAnnotationList()
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

    @objc private func selectTool(_ sender: NSButton) {
        let index = max(0, min(sender.tag, AnnotationTool.allCases.count - 1))
        let tool = AnnotationTool.allCases[index]
        setTool(tool)
        applyCurrentSelectionIfPossible(for: tool)
    }

    private func setTool(_ tool: AnnotationTool) {
        selectedTool = tool
        toolButtons.forEach { current, button in
            button.state = current == tool ? .on : .off
        }
        statusLabel.stringValue = "현재 도구: \(tool.title)"
    }

    private func applyCurrentSelectionIfPossible(for tool: AnnotationTool) {
        switch tool {
        case .highlight:
            addMarkupAnnotation(.highlight, color: Brand.highlight, contents: nil)
        case .underline:
            addMarkupAnnotation(.underline, color: .systemBlue, contents: nil)
        case .strikeout:
            addMarkupAnnotation(.strikeOut, color: .systemRed, contents: nil)
        case .selectedNote:
            addSelectedTextNote()
        case .deletion:
            addDeletionSuggestion()
        case .replacement:
            addReplacementSuggestion()
        default:
            break
        }
    }

    private func addTextBox(at viewPoint: NSPoint? = nil) {
        guard let page = targetPage(for: viewPoint) else { return }
        let bounds = viewPoint.map { centeredBounds(around: $0, on: page) } ?? centeredBounds(on: page)
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = "메모"
        annotation.font = .systemFont(ofSize: 13)
        annotation.color = .clear
        annotation.fontColor = .labelColor
        annotation.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.24)
        addAnnotations([(page, annotation)], select: annotation)
    }

    private func addArrowTextBox(at viewPoint: NSPoint? = nil) {
        guard let page = targetPage(for: viewPoint) else { return }
        let bounds = viewPoint.map { centeredBounds(around: $0, on: page) } ?? centeredBounds(on: page)
        let lineBounds = bounds.insetBy(dx: -70, dy: -30)
        let line = PDFAnnotation(bounds: lineBounds, forType: .line, withProperties: nil)
        line.color = Brand.accent
        line.border = PDFBorder()
        line.border?.lineWidth = 2
        line.startPoint = NSPoint(x: line.bounds.minX, y: line.bounds.minY)
        line.endPoint = NSPoint(x: line.bounds.midX, y: line.bounds.midY)
        line.endLineStyle = .closedArrow

        let text = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        text.contents = "대체/설명 입력"
        text.font = .systemFont(ofSize: 13)
        text.color = .clear
        text.fontColor = .labelColor
        text.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12)
        addAnnotations([(page, line), (page, text)], select: text)
    }

    private func addSelectedTextNote() {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first else { return }
        let note = PDFAnnotation(bounds: selection.bounds(for: page).offsetBy(dx: 12, dy: 12),
                                 forType: .text,
                                 withProperties: nil)
        note.contents = "선택 텍스트 주석: \(selection.string ?? "")"
        note.color = .systemYellow
        addAnnotations([(page, note)], select: note)
    }

    private func addDeletionSuggestion() {
        guard let selection = pdfView.currentSelection else { return }
        var added = addMarkupAnnotation(.strikeOut, color: .systemRed, contents: "삭제 제안", registerUndo: false)
        if let page = selection.pages.first {
            let note = PDFAnnotation(bounds: selection.bounds(for: page).offsetBy(dx: 12, dy: 12),
                                     forType: .text,
                                     withProperties: nil)
            note.contents = "삭제 제안: \(selection.string ?? "")"
            note.color = .systemRed
            added.append((page, note))
        }
        if !added.isEmpty {
            undoStack.append(.add(added))
            refreshAnnotationList()
        }
    }

    private func addReplacementSuggestion() {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first else { return }
        let replacement = prompt("대체 텍스트", message: "선택한 텍스트를 무엇으로 바꿀까요?")
        guard !replacement.isEmpty else { return }
        var added = addMarkupAnnotation(.strikeOut, color: .systemRed, contents: "대체 제안: \(selection.string ?? "") -> \(replacement)", registerUndo: false)
        let bounds = selection.bounds(for: page).offsetBy(dx: 12, dy: 18)
        let annotation = PDFAnnotation(bounds: NSRect(x: bounds.minX, y: bounds.minY, width: max(bounds.width, 180), height: 42),
                                       forType: .freeText,
                                       withProperties: nil)
        annotation.contents = replacement
        annotation.font = .systemFont(ofSize: 12)
        annotation.fontColor = .systemRed
        annotation.color = .clear
        annotation.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10)
        added.append((page, annotation))
        addAnnotations(added, select: annotation)
    }

    @discardableResult
    private func addMarkupAnnotation(_ type: PDFAnnotationSubtype, color: NSColor, contents: String?, registerUndo: Bool = true) -> [(PDFPage, PDFAnnotation)] {
        guard let selection = pdfView.currentSelection else { return [] }
        let selections = selection.selectionsByLine()
        let targets = selections.isEmpty ? [selection] : selections
        var added: [(PDFPage, PDFAnnotation)] = []
        for item in targets {
            for page in item.pages {
                let bounds = item.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                annotation.contents = contents
                page.addAnnotation(annotation)
                added.append((page, annotation))
            }
        }
        if !added.isEmpty, registerUndo {
            undoStack.append(.add(added))
            selectAnnotation(added.last!.1, on: added.last!.0)
            refreshAnnotationList()
        }
        return added
    }

    private func addAnnotations(_ annotations: [(PDFPage, PDFAnnotation)], select annotationToSelect: PDFAnnotation?) {
        for (page, annotation) in annotations {
            page.addAnnotation(annotation)
        }
        undoStack.append(.add(annotations))
        if let annotationToSelect,
           let page = annotations.first(where: { $0.1 === annotationToSelect })?.0 {
            selectAnnotation(annotationToSelect, on: page)
        }
        refreshAnnotationList()
    }

    private func targetPage(for viewPoint: NSPoint?) -> PDFPage? {
        if let viewPoint {
            return pdfView.page(for: viewPoint, nearest: true)
        }
        return pdfView.currentPage
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
        statusLabel.stringValue = "맞춤법 검사 중..."

        let options = CorrectionOptions(useGPT: Settings.shared.useGPT,
                                        correctionStrength: Settings.shared.correctionStrength,
                                        usePublisherRules: Settings.shared.usePublisherRules,
                                        joinAuxiliaryVerbs: Settings.shared.joinAuxiliaryVerbs)

        Task {
            var correctionCount = 0
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                let raw = page.string ?? ""
                let normalized = PDFTextNormalizer.normalizePageText(raw)
                do {
                    let corrected = try await correctionEngine.correct(text: normalized, options: options, glossary: glossaryRules)
                    correctionCount += applyAICorrections(corrected.corrections, pageIndex: pageIndex, in: document)
                } catch {
                    statusLabel.stringValue = "\(pageIndex + 1)쪽 실패: \(error.localizedDescription)"
                }
                statusLabel.stringValue = "맞춤법 검사 중... \(pageIndex + 1) / \(document.pageCount)"
            }
            refreshAnnotationList()
            statusLabel.stringValue = "검사 완료: \(correctionCount)개 AI 교정 표시"
        }
    }

    private func applyAICorrections(_ corrections: [TextCorrection], pageIndex: Int, in document: PDFDocument) -> Int {
        guard !corrections.isEmpty else { return 0 }
        var added: [(PDFPage, PDFAnnotation)] = []
        for correction in corrections {
            let message = "[AI] \(correction.original) -> \(correction.corrected)"
            let selections = document.findString(correction.original, withOptions: [.caseInsensitive])
                .filter { $0.pages.contains { document.index(for: $0) == pageIndex } }
            for selection in selections {
                for page in selection.pages where document.index(for: page) == pageIndex {
                    let bounds = selection.bounds(for: page)
                    guard bounds.width > 0, bounds.height > 0 else { continue }
                    let highlight = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    highlight.color = Brand.correction
                    highlight.contents = message
                    page.addAnnotation(highlight)
                    added.append((page, highlight))
                }
            }
        }
        if !added.isEmpty {
            undoStack.append(.add(added))
        }
        return added.count
    }

    private func refreshAnnotationList() {
        guard let document = pdfView.document else {
            annotationItems = []
            annotationTable.reloadData()
            return
        }
        var items: [AnnotationListItem] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                items.append(AnnotationListItem(pageIndex: pageIndex, annotation: annotation))
            }
        }
        annotationItems = items
        commentCountLabel.stringValue = "\(items.count)개"
        annotationTable.reloadData()
        syncTableSelection()
        updateSelectedCommentPanel()
    }

    private func selectAnnotation(_ annotation: PDFAnnotation, on page: PDFPage) {
        selectedAnnotation = annotation
        selectedAnnotationPage = page
        pdfView.go(to: page)
        statusLabel.stringValue = "선택한 주석: \(annotation.contents ?? annotation.type ?? "주석")"
        syncTableSelection()
        updateSelectedCommentPanel()
    }

    private func syncTableSelection() {
        guard let selectedAnnotation else {
            annotationTable.deselectAll(nil)
            updateSelectedCommentPanel()
            return
        }
        if let index = annotationItems.firstIndex(where: { $0.annotation === selectedAnnotation }) {
            annotationTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            annotationTable.scrollRowToVisible(index)
        }
        annotationTable.reloadData()
    }

    @objc private func editSelectedAnnotation(_ sender: Any?) {
        if selectedAnnotation == nil, annotationTable.selectedRow >= 0 {
            tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: annotationTable))
        }
        guard let annotation = selectedAnnotation, let page = selectedAnnotationPage else { return }
        selectAnnotation(annotation, on: page)
        window?.makeFirstResponder(selectedCommentEditor)
    }

    @objc private func saveSelectedAnnotationNote(_ sender: Any?) {
        guard let annotation = selectedAnnotation, let page = selectedAnnotationPage else { return }
        annotation.contents = selectedCommentEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if annotation.type == "FreeText" {
            annotation.font = .systemFont(ofSize: 13)
        }
        selectAnnotation(annotation, on: page)
        refreshAnnotationList()
        statusLabel.stringValue = "주석 메모 저장됨"
    }

    @objc private func deleteSelectedAnnotation(_ sender: Any?) {
        guard let annotation = selectedAnnotation, let page = selectedAnnotationPage else { return }
        page.removeAnnotation(annotation)
        undoStack.append(.remove([(page, annotation)]))
        selectedAnnotation = nil
        selectedAnnotationPage = nil
        refreshAnnotationList()
    }

    private func edit(_ annotation: PDFAnnotation, on page: PDFPage) {
        let current = annotation.contents ?? ""
        let value = prompt("주석 수정", message: "주석 내용을 수정합니다.", defaultValue: current)
        annotation.contents = value
        if annotation.type == "FreeText" {
            annotation.font = .systemFont(ofSize: 13)
        }
        selectAnnotation(annotation, on: page)
        refreshAnnotationList()
    }

    private func undoLastAction() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .add(let annotations):
            annotations.forEach { page, annotation in page.removeAnnotation(annotation) }
        case .remove(let annotations):
            annotations.forEach { page, annotation in page.addAnnotation(annotation) }
        }
        selectedAnnotation = nil
        selectedAnnotationPage = nil
        refreshAnnotationList()
        statusLabel.stringValue = "되돌림"
    }

    private func updateSelectedCommentPanel() {
        guard let annotation = selectedAnnotation,
              let page = selectedAnnotationPage,
              let document = pdfView.document else {
            selectedCommentTitle.stringValue = "선택한 주석 없음"
            selectedCommentTitle.textColor = .secondaryLabelColor
            selectedCommentEditor.string = ""
            return
        }
        let pageIndex = document.index(for: page) + 1
        let item = AnnotationListItem(pageIndex: max(0, pageIndex - 1), annotation: annotation)
        selectedCommentTitle.stringValue = "\(pageIndex)쪽 · \(item.typeText)"
        selectedCommentTitle.textColor = .labelColor
        selectedCommentEditor.string = annotation.contents ?? ""
    }

    private func centeredBounds(on page: PDFPage) -> NSRect {
        let pageBounds = page.bounds(for: .mediaBox)
        return NSRect(x: pageBounds.midX - 90, y: pageBounds.midY - 24, width: 180, height: 48)
    }

    private func centeredBounds(around viewPoint: NSPoint, on page: PDFPage) -> NSRect {
        let pagePoint = pdfView.convert(viewPoint, to: page)
        return NSRect(x: pagePoint.x - 90, y: pagePoint.y - 24, width: 180, height: 48)
    }

    private func updateControls() {
        guard let document = pdfView.document else {
            pageLabel.stringValue = "0 / 0"
            return
        }
        let current = pdfView.currentPage.map { document.index(for: $0) + 1 } ?? 1
        pageLabel.stringValue = "\(current) / \(document.pageCount)"
    }

    private func prompt(_ title: String, message: String, defaultValue: String = "") -> String {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        return alert.runModal() == .alertFirstButtonReturn ? input.stringValue : defaultValue
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

extension DocumentWindowController: AnnotatingPDFViewDelegate {
    fileprivate func pdfView(_ pdfView: AnnotatingPDFView, didSelect annotation: PDFAnnotation, on page: PDFPage) {
        selectAnnotation(annotation, on: page)
    }

    fileprivate func pdfView(_ pdfView: AnnotatingPDFView, didRequestEdit annotation: PDFAnnotation, on page: PDFPage) {
        edit(annotation, on: page)
    }

    fileprivate func pdfView(_ pdfView: AnnotatingPDFView, didClickEmptyPageAt viewPoint: NSPoint) -> Bool {
        switch selectedTool {
        case .textBox:
            addTextBox(at: viewPoint)
            return true
        case .arrowTextBox:
            addArrowTextBox(at: viewPoint)
            return true
        default:
            selectedAnnotation = nil
            selectedAnnotationPage = nil
            syncTableSelection()
            return false
        }
    }

    fileprivate func pdfViewDidRequestUndo(_ pdfView: AnnotatingPDFView) {
        undoLastAction()
    }

    fileprivate func pdfViewDidRequestDelete(_ pdfView: AnnotatingPDFView) {
        deleteSelectedAnnotation(nil)
    }

    fileprivate func pdfViewDidRequestEditSelected(_ pdfView: AnnotatingPDFView) {
        editSelectedAnnotation(nil)
    }
}

extension DocumentWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        annotationItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard annotationItems.indices.contains(row) else { return nil }
        let item = annotationItems[row]
        let isSelected = selectedAnnotation === item.annotation
        let cell = NSTableCellView()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.backgroundColor = (isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.14)
            : NSColor.controlBackgroundColor).cgColor
        container.layer?.borderWidth = isSelected ? 2 : 0
        container.layer?.borderColor = NSColor.selectedContentBackgroundColor.cgColor
        cell.addSubview(container)

        let pageBadge = NSTextField(labelWithString: item.pageText)
        pageBadge.alignment = .center
        pageBadge.font = .boldSystemFont(ofSize: 12)
        pageBadge.textColor = .white
        pageBadge.wantsLayer = true
        pageBadge.layer?.cornerRadius = 9
        pageBadge.layer?.backgroundColor = (item.typeText == "AI" ? NSColor.systemRed : NSColor.systemBlue).cgColor
        pageBadge.translatesAutoresizingMaskIntoConstraints = false

        let type = NSTextField(labelWithString: item.typeText)
        type.font = .boldSystemFont(ofSize: 12)
        type.textColor = .labelColor
        type.lineBreakMode = .byTruncatingTail
        type.translatesAutoresizingMaskIntoConstraints = false

        let summary = NSTextField(labelWithString: item.summary)
        summary.font = .systemFont(ofSize: 12)
        summary.textColor = isSelected ? .labelColor : .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.maximumNumberOfLines = 2
        summary.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(pageBadge)
        container.addSubview(type)
        container.addSubview(summary)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            container.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            container.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
            container.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2),

            pageBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            pageBadge.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            pageBadge.widthAnchor.constraint(equalToConstant: 34),
            pageBadge.heightAnchor.constraint(equalToConstant: 18),

            type.leadingAnchor.constraint(equalTo: pageBadge.trailingAnchor, constant: 8),
            type.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            type.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

            summary.leadingAnchor.constraint(equalTo: type.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: type.trailingAnchor),
            summary.topAnchor.constraint(equalTo: type.bottomAnchor, constant: 3)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = annotationTable.selectedRow
        guard annotationItems.indices.contains(row),
              let document = pdfView.document,
              let page = document.page(at: annotationItems[row].pageIndex) else { return }
        selectAnnotation(annotationItems[row].annotation, on: page)
        annotationTable.reloadData()
    }
}
