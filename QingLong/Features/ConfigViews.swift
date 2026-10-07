import SwiftUI

// MARK: - 配置文件

/// 面板配置文件列表（`GET /api/configs/files` 返回 [{title, value}]）。
struct ConfigListView: View {

    /// 更多页等已有导航栈的场景传 true，直接作为子页推入。
    var inlineTitle: Bool = false

    @EnvironmentObject private var store: PanelStore

    @State private var files: [ConfigFileItem] = []
    @State private var loaded = false
    @State private var isLoading = false

    var body: some View {
        Group {
            if inlineTitle {
                list
            } else {
                NavigationView { list }
                    .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }

    private var list: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if isLoading && files.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在读取配置文件…")
                        .font(.system(size: Theme.font(12.5)))
                        .foregroundColor(Theme.secondaryText)
                }
            } else if files.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: Theme.font(32)))
                        .foregroundColor(Theme.tertiaryText)
                    Text("没有读取到配置文件")
                        .font(.system(size: Theme.font(14), weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    Text("面板版本较低或权限不足时，可能无法使用该功能。")
                        .font(.system(size: Theme.font(12)))
                        .foregroundColor(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            } else {
                List {
                    ForEach(files) { file in
                        NavigationLink(
                            destination: ConfigEditorView(fileName: file.value, displayName: file.title)
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.plaintext")
                                    .font(.system(size: Theme.font(15)))
                                    .foregroundColor(Theme.info)
                                Text(file.title)
                                    .font(.system(size: Theme.font(14)))
                                    .foregroundColor(Theme.primaryText)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .navigationBarTitle("配置文件", displayMode: .inline)
        .onAppear {
            if !loaded {
                loaded = true
                Task { await reload() }
            }
        }
    }

    private func reload() async {
        isLoading = true
        await store.loadConfigFiles()
        files = store.configFiles
        isLoading = false
    }
}

// MARK: - 配置文件编辑

/// 查看与编辑单个配置文件。
/// 读取走 `GET /api/configs/detail?path=`（新版）或 `GET /api/configs/:file`（旧版），
/// 保存走 `PUT`/`POST /api/configs/save`（body {name, content}），面板侧自动兼容。
struct ConfigEditorView: View {

    let fileName: String
    var displayName: String = ""

    @EnvironmentObject private var store: PanelStore

    @State private var content = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var savedHint = false
    @State private var errorText = ""

    var body: some View {
        ZStack {
            Theme.groupedBackground.edgesIgnoringSafeArea(.all)

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在读取文件内容…")
                        .font(.system(size: Theme.font(12.5)))
                        .foregroundColor(Theme.secondaryText)
                }
            } else {
                VStack(spacing: 0) {
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: Theme.font(12)))
                            .foregroundColor(Theme.danger)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                    }
                    TextEditor(text: $content)
                        .font(.system(size: Theme.font(12.5), design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .overlay(
                            Group {
                                if savedHint {
                                    VStack {
                                        Spacer()
                                        Text("已保存")
                                            .font(.system(size: Theme.font(12), weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(Color.black.opacity(0.75)))
                                            .padding(.bottom, 24)
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                        )
                }
            }
        }
        .navigationBarTitle(displayName.isEmpty ? fileName : displayName, displayMode: .inline)
        .navigationBarItems(trailing: saveButton)
        .onAppear {
            if isLoading {
                Task { await reload() }
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            if isSaving {
                ProgressView()
            } else {
                Text("保存").bold()
            }
        }
        .disabled(isSaving || isLoading)
    }

    private func reload() async {
        content = await store.loadConfigContent(fileName)
        isLoading = false
    }

    private func save() {
        isSaving = true
        errorText = ""
        Task {
            let ok = await store.saveConfigFile(name: fileName, content: content)
            isSaving = false
            if ok {
                savedHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    savedHint = false
                }
            } else {
                errorText = "保存失败，请稍后重试"
            }
        }
    }
}
