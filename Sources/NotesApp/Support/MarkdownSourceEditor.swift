import AppKit
import NotesCore
import SwiftUI

final class MarkdownEditorController: ObservableObject {
    fileprivate weak var textView: NSTextView?

    func toggleBold() { wrapSelection(prefix: MarkdownSyntax.bold.opening, suffix: MarkdownSyntax.bold.closing, placeholder: "bold text") }
    func toggleItalic() { wrapSelection(prefix: MarkdownSyntax.italic.opening, suffix: MarkdownSyntax.italic.closing, placeholder: "italic text") }
    func toggleStrikethrough() { wrapSelection(prefix: MarkdownSyntax.strikethrough.opening, suffix: MarkdownSyntax.strikethrough.closing, placeholder: "strikethrough") }
    func toggleHighlight() { wrapSelection(prefix: MarkdownSyntax.highlight.opening, suffix: MarkdownSyntax.highlight.closing, placeholder: "highlight") }
    func insertInlineCode() { wrapSelection(prefix: "`", suffix: "`", placeholder: "code") }
    func insertWikilink() { wrapSelection(prefix: MarkdownSyntax.wikilink.opening, suffix: MarkdownSyntax.wikilink.closing, placeholder: "Note") }
    func insertMarkdownLink() { wrapSelection(prefix: "[", suffix: "](https://)", placeholder: "link text") }
    func applyHeading() { prefixSelectedLines("## ") }
    func insertBullet() { prefixSelectedLines("- ") }
    func insertNumberedList() { prefixSelectedLines("1. ") }
    func insertQuote() { prefixSelectedLines("> ") }
    func insertTask() { prefixSelectedLines(MarkdownSyntax.taskUnchecked) }
    func insertCodeBlock() { insert("```text\n\n```", cursorOffset: 8) }
    func insertHorizontalRule() { insert("\n---\n") }
    func insertTable() {
        insert("| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |\n")
    }

    func insertMarkdown(_ value: String) { insert(value) }

    func replaceMarkdown(in range: MarkdownSourceRange, with value: String) {
        replace(
            range: NSRange(location: range.lowerBound, length: max(0, range.upperBound - range.lowerBound)),
            with: value,
            selectedRange: NSRange(location: range.lowerBound + value.utf16.count, length: 0)
        )
    }

    func showFindPanel() {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        textView?.performFindPanelAction(item)
    }

    var selectedRange: NSRange? { textView?.selectedRange() }

    func restoreSelection(_ range: NSRange?) {
        guard let textView, let range else { return }
        let location = min(max(0, range.location), textView.string.utf16.count)
        let length = min(max(0, range.length), textView.string.utf16.count - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
        textView.scrollRangeToVisible(NSRange(location: location, length: length))
    }

    func toggleTaskAtSelection() {
        guard let textView else { return }
        let string = textView.string as NSString
        let lineRange = string.lineRange(for: textView.selectedRange())
        var value = string.substring(with: lineRange)
        if value.contains("- [ ] ") {
            value = value.replacingOccurrences(of: MarkdownSyntax.taskUnchecked, with: MarkdownSyntax.taskChecked)
        } else if value.contains(MarkdownSyntax.taskChecked) || value.contains("- [X] ") {
            value = value.replacingOccurrences(of: MarkdownSyntax.taskChecked, with: MarkdownSyntax.taskUnchecked)
                .replacingOccurrences(of: "- [X] ", with: MarkdownSyntax.taskUnchecked)
        } else {
            value = MarkdownSyntax.taskUnchecked + value
        }
        replace(range: lineRange, with: value, selectedRange: NSRange(location: lineRange.location, length: value.utf16.count))
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = range.length > 0
            ? (textView.string as NSString).substring(with: range)
            : placeholder
        let replacement = prefix + selected + suffix
        let selection = range.length > 0
            ? NSRange(location: range.location + replacement.utf16.count, length: 0)
            : NSRange(location: range.location + prefix.utf16.count, length: selected.utf16.count)
        replace(range: range, with: replacement, selectedRange: selection)
    }

    private func prefixSelectedLines(_ prefix: String) {
        guard let textView else { return }
        let string = textView.string as NSString
        let lineRange = string.lineRange(for: textView.selectedRange())
        let original = string.substring(with: lineRange)
        let trailingNewline = original.hasSuffix("\n")
        let lines = original.split(separator: "\n", omittingEmptySubsequences: false)
        var replacement = lines.map { line in
            line.isEmpty ? String(line) : prefix + line
        }.joined(separator: "\n")
        if trailingNewline, !replacement.hasSuffix("\n") { replacement += "\n" }
        replace(
            range: lineRange,
            with: replacement,
            selectedRange: NSRange(location: lineRange.location, length: replacement.utf16.count)
        )
    }

    private func insert(_ value: String, cursorOffset: Int? = nil) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let cursor = range.location + (cursorOffset ?? value.utf16.count)
        replace(range: range, with: value, selectedRange: NSRange(location: cursor, length: 0))
    }

    private func replace(range: NSRange, with replacement: String, selectedRange: NSRange) {
        guard let textView, textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(selectedRange)
    }
}

enum MarkdownEditorSyntaxMode: Equatable {
    case source
    case livePreview
}

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var markdown: String
    let fontFamily: String
    let fontSize: Double
    let controller: MarkdownEditorController
    let syntaxMode: MarkdownEditorSyntaxMode
    let onImportFiles: ([URL]) -> String?
    let onImportImage: (Data, String) -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView()
        textView.onImportFiles = onImportFiles
        textView.onImportImage = onImportImage
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.string = markdown
        textView.backgroundColor = .textBackgroundColor
        configureFont(textView)
        applySyntaxHighlighting(textView)

        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller.textView = textView
        (textView as? MarkdownTextView)?.onImportFiles = onImportFiles
        (textView as? MarkdownTextView)?.onImportImage = onImportImage
        configureFont(textView)
        if textView.string != markdown {
            let selection = textView.selectedRange()
            textView.string = markdown
            textView.setSelectedRange(NSIntersectionRange(selection, NSRange(location: 0, length: markdown.utf16.count)))
        }
        applySyntaxHighlighting(textView)
    }

    private func configureFont(_ textView: NSTextView) {
        let size = CGFloat(fontSize)
        let font: NSFont
        if fontFamily == "System" {
            font = .monospacedSystemFont(ofSize: size, weight: .regular)
        } else {
            font = NSFont(name: fontFamily, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        textView.font = font
        textView.textColor = .textColor
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
    }

    private func applySyntaxHighlighting(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let baseFont = textView.font ?? .monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.textColor], range: fullRange)
        let document = MarkdownParser().parse(textView.string)
        for block in document.blocks {
            highlight(block: block, storage: storage, baseFont: baseFont)
        }
        storage.endEditing()
        textView.typingAttributes = [.font: baseFont, .foregroundColor: NSColor.textColor]
    }

    private func highlight(block: MarkdownBlock, storage: NSTextStorage, baseFont: NSFont) {
        let range = clamped(block.range, length: storage.length)
        switch block.kind {
        case .heading(let level, let inlines):
            let size = syntaxMode == .livePreview ? max(CGFloat(fontSize), 29 - CGFloat(level * 2)) : CGFloat(fontSize)
            storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.labelColor], range: range)
            highlight(inlines: inlines, storage: storage, baseFont: baseFont)
        case .paragraph(let inlines):
            highlight(inlines: inlines, storage: storage, baseFont: baseFont)
        case .fencedCode:
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15)], range: range)
        case .comment:
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        case .callout(let callout):
            storage.addAttributes([.foregroundColor: NSColor.systemBlue, .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.08)], range: range)
            callout.blocks.forEach { highlight(block: $0, storage: storage, baseFont: baseFont) }
        case .blockquote(let blocks):
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            blocks.forEach { highlight(block: $0, storage: storage, baseFont: baseFont) }
        case .list(let list):
            list.items.flatMap(\.blocks).forEach { highlight(block: $0, storage: storage, baseFont: baseFont) }
        case .table:
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular), range: range)
        case .math:
            storage.addAttributes([.font: NSFont(name: "Times New Roman", size: CGFloat(fontSize + 1)) ?? baseFont, .foregroundColor: NSColor.systemPurple], range: range)
        case .footnoteDefinition(_, let blocks):
            blocks.forEach { highlight(block: $0, storage: storage, baseFont: baseFont) }
        case .horizontalRule:
            storage.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: range)
        }
    }

    private func highlight(inlines: [MarkdownInline], storage: NSTextStorage, baseFont: NSFont) {
        for inline in inlines {
            let range = clamped(inline.range, length: storage.length)
            guard range.length > 0 else { continue }
            switch inline.kind {
            case .strong(let children):
                storage.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask), range: range)
                highlight(inlines: children, storage: storage, baseFont: baseFont)
            case .emphasis(let children):
                storage.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask), range: range)
                highlight(inlines: children, storage: storage, baseFont: baseFont)
            case .strongEmphasis(let children):
                let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                storage.addAttribute(.font, value: NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask), range: range)
                highlight(inlines: children, storage: storage, baseFont: baseFont)
            case .strikethrough(let children):
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                highlight(inlines: children, storage: storage, baseFont: baseFont)
            case .highlight(let children):
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
                highlight(inlines: children, storage: storage, baseFont: baseFont)
            case .code:
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.22)], range: range)
            case .link, .wikilink, .embed:
                storage.addAttributes([.foregroundColor: NSColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            case .image:
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
            case .math:
                storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
            case .comment:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .text, .footnoteReference, .softBreak, .hardBreak:
                break
            }
        }
    }

    private func clamped(_ range: MarkdownSourceRange, length: Int) -> NSRange {
        let location = min(max(0, range.lowerBound), length)
        let upper = min(max(location, range.upperBound), length)
        return NSRange(location: location, length: upper - location)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor

        init(parent: MarkdownSourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.markdown = textView.string
            let parent = parent
            DispatchQueue.main.async { parent.applySyntaxHighlighting(textView) }
        }
    }
}

private final class MarkdownTextView: NSTextView {
    private let pairs: [String: String] = ["[": "]", "(": ")", "{": "}", "\"": "\"", "`": "`"]
    var onImportFiles: (([URL]) -> String?)?
    var onImportImage: ((Data, String) -> String?)?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty, let markdown = onImportFiles?(urls) {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        if let png = pasteboard.data(forType: .png), let markdown = onImportImage?(png, "png") {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]),
           let markdown = onImportImage?(png, "png") {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty, let markdown = onImportFiles?(urls) {
            insertText(markdown, replacementRange: selectedRange())
            return true
        }
        return super.performDragOperation(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let value = insertString as? String, value.count == 1 else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let effectiveRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if let closing = pairs[value] {
            let selected = effectiveRange.length > 0
                ? (string as NSString).substring(with: effectiveRange)
                : ""
            let replacement = value + selected + closing
            super.insertText(replacement, replacementRange: effectiveRange)
            setSelectedRange(NSRange(location: effectiveRange.location + value.utf16.count, length: selected.utf16.count))
            return
        }

        if pairs.values.contains(value), effectiveRange.length == 0,
           effectiveRange.location < (string as NSString).length,
           (string as NSString).substring(with: NSRange(location: effectiveRange.location, length: 1)) == value {
            setSelectedRange(NSRange(location: effectiveRange.location + 1, length: 0))
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }
}
