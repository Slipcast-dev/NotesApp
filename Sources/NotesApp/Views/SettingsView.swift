import NotesCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings()

    private let fonts = [
        "System", "Segoe UI", "Arial", "Calibri", "Consolas",
        "Helvetica Neue", "Avenir Next", "Times New Roman", "Georgia", "Menlo"
    ]

    var body: some View {
        TabView {
            Form {
                Picker(store.text("language"), selection: $draft.language) {
                    Text(store.text("russian")).tag(AppLanguage.russian)
                    Text(store.text("english")).tag(AppLanguage.english)
                }

                Toggle(store.text("autoSave"), isOn: $draft.autoSave)

                Picker(store.text("defaultSorting"), selection: $draft.defaultSorting) {
                    ForEach(NoteSorting.allCases) { sorting in
                        Text(store.sortingTitle(sorting)).tag(sorting)
                    }
                }

                HStack {
                    Spacer()
                    Button(store.text("reset")) {
                        draft = AppSettings()
                    }
                    Button(store.text("save")) {
                        store.applySettings(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .tabItem {
                Label(store.text("general"), systemImage: "gearshape")
            }

            Form {
                Picker(store.text("theme"), selection: $draft.theme) {
                    Text(store.text("system")).tag(AppTheme.system)
                    Text(store.text("light")).tag(AppTheme.light)
                    Text(store.text("dark")).tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)

                Picker(store.text("font"), selection: $draft.fontFamily) {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }

                HStack {
                    Text(store.text("fontSize"))
                    Slider(value: $draft.fontSize, in: 10...28, step: 1)
                    Text("\(Int(draft.fontSize))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }

                HStack {
                    Spacer()
                    Button(store.text("save")) {
                        store.applySettings(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .tabItem {
                Label(store.text("appearance"), systemImage: "paintbrush")
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(store.text("currentFolder"))
                    .font(.headline)
                Text(store.storageDirectory.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

                Text(store.text("storageHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button(store.text("chooseStorage")) {
                    if let directory = PlatformServices.chooseStorageDirectory(startingAt: store.storageDirectory) {
                        store.chooseStorageDirectory(directory)
                        draft = store.settings
                    }
                }

                Spacer()
            }
            .padding(22)
            .tabItem {
                Label(store.text("storage"), systemImage: "externaldrive")
            }
        }
        .frame(width: 540, height: 360)
        .onAppear {
            draft = store.settings
        }
    }
}
