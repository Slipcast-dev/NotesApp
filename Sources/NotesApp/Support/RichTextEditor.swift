import AppKit
import Combine
import SwiftUI

enum RichTextCodec {
    static func attributedString(from storedValue: String, defaultFont: NSFont) -> NSAttributedString {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{\\rtf"),
           let data = storedValue.data(using: .utf8),
           let value = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return value
        }

        return NSAttributedString(
            string: storedValue,
            attributes: [
                .font: defaultFont,
                .foregroundColor: NSColor.textColor
            ]
        )
    }

    static func storedValue(from value: NSAttributedString) -> String {
        let range = NSRange(location: 0, length: value.length)
        guard let data = try? value.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ), let string = String(data: data, encoding: .utf8) else {
            return value.string
        }
        return string
    }

    static func plainText(from storedValue: String) -> String {
        attributedString(from: storedValue, defaultFont: .systemFont(ofSize: 14)).string
    }

    static func font(family: String, size: Double) -> NSFont {
        let pointSize = CGFloat(max(8, min(36, size)))
        guard family != "System", let font = NSFont(name: family, size: pointSize) else {
            return .systemFont(ofSize: pointSize)
        }
        return font
    }
}

final class RichTextEditorController: ObservableObject {
    weak var textView: NSTextView?
    private var commitHandler: ((String) -> Void)?

    func connect(textView: NSTextView, commit: @escaping (String) -> Void) {
        self.textView = textView
        commitHandler = commit
    }

    func toggleBold() {
        applyFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        applyFontTrait(.italicFontMask)
    }

    func applyHeading() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = ensuredSelection(placeholder: "Heading")
        let font = NSFontManager.shared.convert(
            NSFont.systemFont(ofSize: 24, weight: .bold),
            toHaveTrait: .boldFontMask
        )
        storage.addAttributes([.font: font], range: range)
        commitChanges()
    }

    func transformSelection(_ transform: (String) -> String) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = ensuredSelection(placeholder: "Text")
        let value = (storage.string as NSString).substring(with: range)
        storage.replaceCharacters(in: range, with: transform(value))
        textView.setSelectedRange(NSRange(location: range.location, length: transform(value).utf16.count))
        commitChanges()
    }

    func insertChecklist() {
        guard let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let selected = selection.length > 0 ? (storage.string as NSString).substring(with: selection) : "Checklist item"
        let replacement = selected
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "☐ " + $0 }
            .joined(separator: "\n")
        replaceSelection(with: replacement)
    }

    func toggleChecklistItem() {
        guard let textView, let storage = textView.textStorage else { return }
        let source = storage.string as NSString
        guard source.length > 0 else { return }
        let caret = min(textView.selectedRange().location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: caret, length: 0))
        let line = source.substring(with: lineRange)
        if line.hasPrefix("☐") {
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 1), with: "☑")
        } else if line.hasPrefix("☑") {
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 1), with: "☐")
        } else {
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "☐ ")
        }
        commitChanges()
    }

    func insertTable() {
        let table = """

        ┌──────────────┬──────────────┐
        │              │              │
        ├──────────────┼──────────────┤
        │              │              │
        └──────────────┴──────────────┘

        """
        replaceSelection(with: table, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    func insertInternalLink(title: String) {
        replaceSelection(with: "[[\(title.trimmingCharacters(in: .whitespacesAndNewlines))]]")
    }

    func selectedInternalLinkTitle() -> String? {
        guard let textView, let storage = textView.textStorage else { return nil }
        let source = storage.string as NSString
        let selection = textView.selectedRange()
        var value = selection.length > 0 ? source.substring(with: selection) : ""

        if value.isEmpty,
           let expression = try? NSRegularExpression(pattern: #"\[\[[^\]]+\]\]"#),
           let match = expression.matches(
               in: source as String,
               range: NSRange(location: 0, length: source.length)
           ).first(where: { NSLocationInRange(selection.location, $0.range) }) {
            value = source.substring(with: match.range)
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("[["), value.hasSuffix("]]"), value.count > 4 {
            value = String(value.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }

    private func applyFontTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = ensuredSelection(placeholder: "Text")
        let existing = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? textView.font
            ?? .systemFont(ofSize: 14)
        let hasTrait = NSFontManager.shared.traits(of: existing).contains(trait)
        let font = hasTrait
            ? NSFontManager.shared.convert(existing, toNotHaveTrait: trait)
            : NSFontManager.shared.convert(existing, toHaveTrait: trait)
        storage.addAttribute(.font, value: font, range: range)
        commitChanges()
    }

    private func ensuredSelection(placeholder: String) -> NSRange {
        guard let textView, let storage = textView.textStorage else { return NSRange(location: 0, length: 0) }
        let selection = textView.selectedRange()
        if selection.length > 0 {
            return selection
        }
        storage.replaceCharacters(in: selection, with: placeholder)
        let range = NSRange(location: selection.location, length: placeholder.utf16.count)
        textView.setSelectedRange(range)
        return range
    }

    private func replaceSelection(with replacement: String, font: NSFont? = nil) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if let font {
            storage.replaceCharacters(
                in: range,
                with: NSAttributedString(string: replacement, attributes: [.font: font])
            )
        } else {
            storage.replaceCharacters(in: range, with: replacement)
        }
        textView.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
        commitChanges()
    }

    private func commitChanges() {
        guard let textView else { return }
        textView.didChangeText()
        commitHandler?(RichTextCodec.storedValue(from: textView.attributedString()))
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var content: String
    let fontFamily: String
    let fontSize: Double
    let controller: RichTextEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(content: $content)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindPanel = true

        let font = RichTextCodec.font(family: fontFamily, size: fontSize)
        textView.font = font
        textView.textStorage?.setAttributedString(
            RichTextCodec.attributedString(from: content, defaultFont: font)
        )
        context.coordinator.lastStoredValue = content
        controller.connect(textView: textView) { value in
            context.coordinator.lastStoredValue = value
            content = value
        }
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.content = $content
        controller.connect(textView: textView) { value in
            context.coordinator.lastStoredValue = value
            content = value
        }

        let font = RichTextCodec.font(family: fontFamily, size: fontSize)
        textView.typingAttributes[.font] = font

        if content != context.coordinator.lastStoredValue {
            context.coordinator.isApplyingExternalValue = true
            textView.textStorage?.setAttributedString(
                RichTextCodec.attributedString(from: content, defaultFont: font)
            )
            context.coordinator.lastStoredValue = content
            context.coordinator.isApplyingExternalValue = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var content: Binding<String>
        var lastStoredValue = ""
        var isApplyingExternalValue = false

        init(content: Binding<String>) {
            self.content = content
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalValue,
                  let textView = notification.object as? NSTextView else { return }
            let value = RichTextCodec.storedValue(from: textView.attributedString())
            lastStoredValue = value
            content.wrappedValue = value
        }
    }
}
