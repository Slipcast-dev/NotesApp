import NotesCore
import SwiftUI

struct MarkdownReadingView: View {
    @Binding var markdown: String
    let language: AppLanguage
    let allowsTableEditing: Bool
    let onEditTable: (MarkdownSourceRange) -> Void

    var body: some View {
        let content = readingContent
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !content.tasks.isEmpty {
                    HStack(spacing: 8) {
                        Label(L10n.text("tasks", language: language), systemImage: "checklist")
                            .font(.headline)
                        Spacer()
                        Text(L10n.format(
                            "completedTasks",
                            language: language,
                            content.tasks.filter { $0.state == .checked }.count,
                            content.tasks.count
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)
                }
                if let frontmatter = content.document.frontmatter, !frontmatter.keyOrder.isEmpty {
                    PropertiesSummary(frontmatter: frontmatter)
                }
                ForEach(content.document.blocks) { block in
                    ReadingBlockView(
                        block: block,
                        taskAssignments: content.taskAssignments,
                        language: language,
                        allowsTableEditing: allowsTableEditing,
                        onToggleTask: toggleTask,
                        onEditTable: onEditTable
                    )
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .textSelection(.enabled)
    }

    private func toggleTask(_ task: MarkdownTaskOccurrence) {
        markdown = MarkdownInteractiveEditor().togglingTask(in: markdown, occurrence: task)
    }

    private var readingContent: ReadingContent {
        let document = MarkdownParser().parse(markdown)
        let tasks = MarkdownInteractiveEditor().tasks(in: markdown)
        var itemIDs: [UUID] = []
        collectTaskItemIDs(in: document.blocks, into: &itemIDs)
        return ReadingContent(
            document: document,
            tasks: tasks,
            taskAssignments: Dictionary(uniqueKeysWithValues: zip(itemIDs, tasks))
        )
    }

    private func collectTaskItemIDs(in blocks: [MarkdownBlock], into result: inout [UUID]) {
        for block in blocks {
            switch block.kind {
            case .list(let list):
                for item in list.items {
                    if item.task != nil { result.append(item.id) }
                    collectTaskItemIDs(in: item.blocks, into: &result)
                }
            case .blockquote(let blocks), .footnoteDefinition(_, let blocks):
                collectTaskItemIDs(in: blocks, into: &result)
            case .callout(let callout):
                collectTaskItemIDs(in: callout.blocks, into: &result)
            default:
                break
            }
        }
    }
}

private struct ReadingContent {
    let document: MarkdownDocument
    let tasks: [MarkdownTaskOccurrence]
    let taskAssignments: [UUID: MarkdownTaskOccurrence]
}

private struct ReadingBlockView: View {
    let block: MarkdownBlock
    let taskAssignments: [UUID: MarkdownTaskOccurrence]
    let language: AppLanguage
    let allowsTableEditing: Bool
    let onToggleTask: (MarkdownTaskOccurrence) -> Void
    let onEditTable: (MarkdownSourceRange) -> Void
    private let renderer = MarkdownRenderer()

    var body: some View {
        switch block.kind {
        case .heading(let level, _):
            Text(renderer.plainText(document))
                .font(headingFont(level))
                .fontWeight(.bold)
        case .paragraph:
            Text(inlineAttributed)
                .font(.body)
                .lineSpacing(4)
        case .list(let list):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        if let task = item.task {
                            if let occurrence = taskAssignments[item.id] {
                                Button { onToggleTask(occurrence) } label: {
                                    taskCheckbox(state: task)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.text("toggleTask", language: language))
                            } else {
                                taskCheckbox(state: task)
                            }
                        } else {
                            Text(listMarker(list, index: index)).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(item.blocks) {
                                ReadingBlockView(
                                    block: $0,
                                    taskAssignments: taskAssignments,
                                    language: language,
                                    allowsTableEditing: allowsTableEditing,
                                    onToggleTask: onToggleTask,
                                    onEditTable: onEditTable
                                )
                            }
                        }
                        .opacity(item.task == .checked ? 0.62 : 1)
                    }
                }
            }
            .padding(.leading, 8)
        case .blockquote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(Color.secondary.opacity(0.45)).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(blocks) {
                        ReadingBlockView(
                            block: $0,
                            taskAssignments: taskAssignments,
                            language: language,
                            allowsTableEditing: allowsTableEditing,
                            onToggleTask: onToggleTask,
                            onEditTable: onEditTable
                        )
                    }
                }
            }
        case .callout(let callout):
            VStack(alignment: .leading, spacing: 9) {
                Label(callout.title ?? callout.type.capitalized, systemImage: "info.circle.fill")
                    .font(.headline)
                ForEach(callout.blocks) {
                    ReadingBlockView(
                        block: $0,
                        taskAssignments: taskAssignments,
                        language: language,
                        allowsTableEditing: allowsTableEditing,
                        onToggleTask: onToggleTask,
                        onEditTable: onEditTable
                    )
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor.opacity(0.28)))
        case .fencedCode(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language { Text(language).font(.caption.bold()).foregroundStyle(.secondary) }
                Text(code).font(.system(.body, design: .monospaced))
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case .table(let table):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L10n.text("table", language: language), systemImage: "tablecells")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if allowsTableEditing {
                        Button(L10n.text("editTable", language: language)) {
                            onEditTable(block.range)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                                tableCell(
                                    inlineText(cell),
                                    alignment: table.alignments.indices.contains(column) ? table.alignments[column] : .none,
                                    isHeader: true
                                )
                            }
                        }
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(table.header.indices, id: \.self) { column in
                                    tableCell(
                                        row.indices.contains(column) ? inlineText(row[column]) : "",
                                        alignment: table.alignments.indices.contains(column) ? table.alignments[column] : .none,
                                        isHeader: false
                                    )
                                }
                            }
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
        case .horizontalRule:
            Divider()
        case .footnoteDefinition(let label, let blocks):
            HStack(alignment: .top) {
                Text("[\(label)]").font(.caption.monospaced()).foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    ForEach(blocks) {
                        ReadingBlockView(
                            block: $0,
                            taskAssignments: taskAssignments,
                            language: language,
                            allowsTableEditing: allowsTableEditing,
                            onToggleTask: onToggleTask,
                            onEditTable: onEditTable
                        )
                    }
                }
            }
        case .comment:
            EmptyView()
        case .math(let value):
            Text(value)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(.purple)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var document: MarkdownDocument {
        MarkdownDocument(frontmatter: nil, blocks: [block], source: "")
    }

    private var inlineAttributed: AttributedString {
        let markdown = renderer.renderMarkdown(document)
        return (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(renderer.plainText(document))
    }

    private func inlineText(_ value: [MarkdownInline]) -> String {
        renderer.plainText(MarkdownDocument(
            frontmatter: nil,
            blocks: [MarkdownBlock(kind: .paragraph(value), range: MarkdownSourceRange(0, 0))],
            source: ""
        ))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        default: return .headline
        }
    }

    private func listMarker(_ list: MarkdownList, index: Int) -> String {
        switch list.kind {
        case .unordered: return "•"
        case .ordered(let start, _): return "\(start + index)."
        }
    }

    private func taskCheckbox(state: MarkdownTaskState) -> some View {
        Image(systemName: state == .checked ? "checkmark.square.fill" : "square")
            .foregroundStyle(state == .checked ? Color.accentColor : Color.secondary)
    }

    private func tableCell(
        _ value: String,
        alignment: MarkdownTable.Alignment,
        isHeader: Bool
    ) -> some View {
        Text(value.isEmpty ? " " : value)
            .fontWeight(isHeader ? .semibold : .regular)
            .lineLimit(nil)
            .frame(minWidth: 120, alignment: frameAlignment(alignment))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.28), lineWidth: 0.5))
    }

    private func frameAlignment(_ alignment: MarkdownTable.Alignment) -> Alignment {
        switch alignment {
        case .center: return .center
        case .right: return .trailing
        case .none, .left: return .leading
        }
    }

}

private struct PropertiesSummary: View {
    let frontmatter: YAMLFrontmatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(frontmatter.keyOrder, id: \.self) { key in
                if let value = frontmatter.properties[key] {
                    HStack(alignment: .firstTextBaseline) {
                        Text(key).fontWeight(.semibold).frame(width: 110, alignment: .leading)
                        Text(display(value)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func display(_ value: YAMLValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "—"
        case .array(let values): return values.map(display).joined(separator: ", ")
        case .object(let values): return values.map { "\($0.key): \(display($0.value))" }.joined(separator: ", ")
        }
    }
}
