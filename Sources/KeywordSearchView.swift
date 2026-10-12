import SwiftUI

struct KeywordSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ShopSearchModel()
    @State private var keyword = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("店名・地名・料理名", text: $keyword)
                            .onSubmit { Task { await model.search(keyword: keyword) } }
                        Button("検索") {
                            Task { await model.search(keyword: keyword) }
                        }
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty
                                  || model.isSearching)
                    }
                    if model.isSearching {
                        ProgressView()
                    } else if !model.message.isEmpty {
                        Text(model.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("例：「渋谷 ラーメン」、店名の一部")
                }
                Section("候補") {
                    ForEach(model.candidates) { candidate in
                        NavigationLink {
                            ShopEditView(mode: .new(ShopDraft(candidate: candidate)),
                                         onSaved: { dismiss() })
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                Text(candidate.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("キーワードで探す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
