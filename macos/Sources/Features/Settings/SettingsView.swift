import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let openInEditor: (String) -> Void

    private enum SidebarItem: Hashable {
        case section(SettingsSection)
        case file(String)
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { model.selectedFile.map(SidebarItem.file) ?? model.selectedSection.map(SidebarItem.section) },
            set: { item in
                switch item {
                case .section(let section):
                    model.selectedFile = nil
                    model.selectedSection = section
                case .file(let file):
                    model.selectedSection = nil
                    model.selectedFile = file
                case nil:
                    model.selectedFile = nil
                    model.selectedSection = nil
                }
            })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    ForEach(SettingsSection.allCases) { Text($0.rawValue).tag(SidebarItem.section($0)) }
                }
                if !model.files.isEmpty {
                    Section("Files") {
                        ForEach(model.files, id: \.self) { file in
                            Text((file as NSString).lastPathComponent)
                                .help(file)
                                .tag(SidebarItem.file(file))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header.padding(10)
                    Divider()
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.sourcePickerCompact, SourcePicker.isCompact(width: geo.size.width, files: model.files))
            }
        }
        .onAppear {
            if model.selectedSection == nil && model.selectedFile == nil { model.selectedSection = .font }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search settings", text: $model.search).textFieldStyle(.roundedBorder)
            }
            if let file = model.selectedFile {
                HStack {
                    Text(file).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Open in Editor") { openInEditor(file) }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.search.isEmpty, model.selectedFile == nil, model.selectedSection == .keybindings {
            KeybindSettingsView(model: model)
        } else {
            let options = model.visibleOptions
            if options.isEmpty {
                Text("No matching settings.").foregroundStyle(.secondary)
            } else {
                List(options) { SettingsRowView(model: model, option: $0) }
            }
        }
    }
}
