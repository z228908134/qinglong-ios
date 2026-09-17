//
//  LogTextDetailView.swift
//  纯文本日志查看器：等宽字体、可复制、可分享。
//

import SwiftUI

struct LogTextDetailView: View {

    let title: String
    let content: String
    var subtitle: String? = nil
    var showsDoneButton: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var lineCount: Int {
        content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(content.isEmpty ? "（暂无日志内容）" : content)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(Color(.systemBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let subtitle {
                    Text(subtitle)
                }
                Text("\(lineCount) 行")
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        UIPasteboard.general.string = content
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    ShareLink(item: content) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
