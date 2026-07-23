import NotesCore
import SwiftUI

private struct TableCellID: Hashable {
    let row: Int
    let column: Int
}

struct MarkdownTableEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MarkdownTableDraft
    @State private var selected = TableCellID(row: 0, column: 0)
    @FocusState private var focused: TableCellID?

    let language: AppLanguage
    let onSave: (MarkdownTableDraft) -> Void

    init(draft: MarkdownTableDraft, language: AppLanguage, onSave: @escaping (MarkdownTableDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.language = language
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            table
            Divider()
            footer
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 430, idealHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(text("tableEditor"), systemImage: "tablecells")
                    .font(.title2.bold())
                Spacer()
                Text(text("tableMarkdownHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Menu {
                    Button(text("addRowAbove")) { insertRow(at: selected.row) }
                    Button(text("addRowBelow")) { insertRow(at: selected.row + 1) }
                    Divider()
                    Button(text("moveRowUp")) { moveRow(by: -1) }
                    Button(text("moveRowDown")) { moveRow(by: 1) }
                    Divider()
                    Button(text("deleteRow"), role: .destructive) { deleteRow() }
                        .disabled(draft.rowCount <= 1)
                } label: { Label(text("rows"), systemImage: "rectangle.split.1x2") }

                Menu {
                    Button(text("addColumnLeft")) { insertColumn(at: selected.column) }
                    Button(text("addColumnRight")) { insertColumn(at: selected.column + 1) }
                    Divider()
                    Button(text("moveColumnLeft")) { moveColumn(by: -1) }
                    Button(text("moveColumnRight")) { moveColumn(by: 1) }
                    Divider()
                    Button(text("deleteColumn"), role: .destructive) { deleteColumn() }
                        .disabled(draft.columnCount <= 1)
                } label: { Label(text("columns"), systemImage: "rectangle.split.2x1") }

                Menu {
                    alignmentButton(.left, title: text("alignLeft"), icon: "text.alignleft")
                    alignmentButton(.center, title: text("alignCenter"), icon: "text.aligncenter")
                    alignmentButton(.right, title: text("alignRight"), icon: "text.alignright")
                    alignmentButton(.none, title: text("alignDefault"), icon: "text.justify")
                } label: { Label(text("alignment"), systemImage: "text.alignleft") }

                Spacer()
                Text(String(format: text("tableSize"), draft.rowCount, draft.columnCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .padding(18)
    }

    private var table: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(draft.cells.indices, id: \.self) { row in
                    GridRow {
                        Text(row == 0 ? text("headerRow") : "\(row)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58)
                            .padding(.vertical, 9)
                            .background(row == selected.row ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))

                        ForEach(draft.cells[row].indices, id: \.self) { column in
                            TextField(
                                row == 0 ? text("columnHeader") : text("cellValue"),
                                text: binding(row: row, column: column)
                            )
                            .textFieldStyle(.plain)
                            .font(row == 0 ? .body.bold() : .body)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .frame(minWidth: 150, idealWidth: 190)
                            .background(cellBackground(row: row, column: column))
                            .overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                            .focused($focused, equals: TableCellID(row: row, column: column))
                            .onTapGesture { select(row: row, column: column) }
                            .onSubmit { advance(after: TableCellID(row: row, column: column)) }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var footer: some View {
        HStack {
            Text(text("tableKeyboardHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(text("cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(text("apply")) {
                onSave(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func binding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: { draft.cells[row][column] },
            set: {
                draft.cells[row][column] = $0
                selected = TableCellID(row: row, column: column)
            }
        )
    }

    private func cellBackground(row: Int, column: Int) -> Color {
        if selected == TableCellID(row: row, column: column) { return Color.accentColor.opacity(0.13) }
        return row == 0 ? Color.secondary.opacity(0.1) : Color.clear
    }

    private func select(row: Int, column: Int) {
        selected = TableCellID(row: row, column: column)
        focused = selected
    }

    private func insertRow(at index: Int) {
        draft.insertRow(at: index)
        select(row: min(index, draft.rowCount - 1), column: selected.column)
    }

    private func deleteRow() {
        draft.removeRow(at: selected.row)
        select(row: min(selected.row, draft.rowCount - 1), column: selected.column)
    }

    private func moveRow(by delta: Int) {
        let target = selected.row + delta
        guard draft.cells.indices.contains(target) else { return }
        draft.moveRow(from: selected.row, to: target)
        select(row: target, column: selected.column)
    }

    private func insertColumn(at index: Int) {
        draft.insertColumn(at: index)
        select(row: selected.row, column: min(index, draft.columnCount - 1))
    }

    private func deleteColumn() {
        draft.removeColumn(at: selected.column)
        select(row: selected.row, column: min(selected.column, draft.columnCount - 1))
    }

    private func moveColumn(by delta: Int) {
        let target = selected.column + delta
        guard (0..<draft.columnCount).contains(target) else { return }
        draft.moveColumn(from: selected.column, to: target)
        select(row: selected.row, column: target)
    }

    private func alignmentButton(_ alignment: MarkdownTable.Alignment, title: String, icon: String) -> some View {
        Button {
            draft.alignments[selected.column] = alignment
        } label: {
            if draft.alignments[selected.column] == alignment { Label(title, systemImage: "checkmark") }
            else { Label(title, systemImage: icon) }
        }
    }

    private func advance(after cell: TableCellID) {
        if cell.column + 1 < draft.columnCount { select(row: cell.row, column: cell.column + 1) }
        else if cell.row + 1 < draft.rowCount { select(row: cell.row + 1, column: 0) }
        else {
            draft.insertRow(at: draft.rowCount)
            select(row: draft.rowCount - 1, column: 0)
        }
    }

    private func text(_ key: String) -> String { L10n.text(key, language: language) }
}
