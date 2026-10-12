import SwiftUI
import SwiftData

// 入力中の店情報（保存前の下書き）
struct ShopDraft {
    var name = ""
    var address = ""
    var latitude: Double?
    var longitude: Double?
    var phone: String?
    var url: String?
    var memo = ""
    var source: ShopSource = .manual
    var prefillVisitDate: Date? = nil          // 写真から登録：来店日の初期値
    var prefillPhoto: ProcessedPhoto? = nil    // 写真から登録：来店記録に付ける写真
}

extension ShopDraft {
    init(candidate c: ShopCandidate) {
        self.init(name: c.name, address: c.address,
                  latitude: c.latitude, longitude: c.longitude,
                  phone: c.phone, url: c.url, memo: "", source: .keyword)
    }
}

struct ShopEditView: View {
    enum Mode {
        case new(ShopDraft)
        case edit(Shop)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    let mode: Mode
    var onSaved: (() -> Void)? = nil

    @State private var draft = ShopDraft()
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var newTagName = ""
    @State private var showDeleteConfirm = false
    @State private var loaded = false

    // 新規登録時の来店記録（D-20）
    @State private var visited = false
    @State private var visitDate = Date.now
    @State private var visitRating: Double?
    @State private var visitMemo = ""

    private var isNew: Bool {
        if case .new = mode { return true } else { return false }
    }

    var body: some View {
        Form {
            Section("お店") {
                TextField("店名（必須）", text: $draft.name)
                TextField("住所", text: $draft.address, axis: .vertical)
                if let phone = draft.phone, !phone.isEmpty {
                    LabeledContent("電話", value: phone)
                }
            }
            if isNew {
                Section {
                    Picker("状態", selection: $visited) {
                        Text("行きたい").tag(false)
                        Text("行った").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if visited {
                        DatePicker("来店日", selection: $visitDate, in: ...Date.now,
                                   displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))   // 日本語表示（I-22）
                        StarRatingInput(rating: $visitRating)
                        TextField("来店メモ（食べたもの・感想など）", text: $visitMemo, axis: .vertical)
                            .lineLimit(2...6)
                        if let photo = draft.prefillPhoto {
                            HStack(spacing: 12) {
                                ThumbnailImage(data: photo.thumbnailData, size: 56)
                                Text("この写真を来店記録に付けます")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("状態")
                } footer: {
                    if draft.prefillPhoto != nil && !visited {
                        Text("「行きたい」で登録すると、写真は保存されません。")
                    }
                }
            }
            Section("タグ") {
                TagChipsView(tags: allTags, selected: $selectedTagIDs)
                HStack {
                    TextField("新しいタグ", text: $newTagName)
                    Button("追加") { addNewTag() }
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("店メモ") {
                TextField("メモ", text: $draft.memo, axis: .vertical)
                    .lineLimit(3...8)
            }
            if !isNew {
                Section {
                    Button("このお店を削除", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(isNew ? "お店を登録" : "お店を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("このお店を削除しますか？",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteShop() }
        } message: {
            Text("来店記録と写真もすべて削除されます。元に戻せません。")
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .new(let initial):
            draft = initial
            // 写真から来た場合は「行った」・来店日＝撮影日で始める
            if initial.prefillPhoto != nil || initial.prefillVisitDate != nil {
                visited = true
                visitDate = min(initial.prefillVisitDate ?? .now, .now)
            }
        case .edit(let shop):
            draft = ShopDraft(name: shop.name, address: shop.address,
                              latitude: shop.latitude, longitude: shop.longitude,
                              phone: shop.phone, url: shop.url,
                              memo: shop.memo, source: shop.source)
            selectedTagIDs = Set(shop.tags.map(\.id))
        }
    }

    private func addNewTag() {
        if let tag = TagRules.findOrCreate(name: newTagName, in: context, existing: allTags) {
            selectedTagIDs.insert(tag.id)
        }
        newTagName = ""
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tags = allTags.filter { selectedTagIDs.contains($0.id) }

        switch mode {
        case .new:
            let shop = Shop(name: name, address: draft.address,
                            latitude: draft.latitude, longitude: draft.longitude,
                            source: draft.source, wantToGo: !visited)
            shop.phone = draft.phone
            shop.url = draft.url
            shop.memo = draft.memo
            context.insert(shop)
            shop.tags = tags
            if visited {
                let visit = Visit(date: visitDate, rating: visitRating, memo: visitMemo)
                shop.visits.append(visit)
                if let photo = draft.prefillPhoto {
                    visit.photos.append(Photo(imageData: photo.imageData,
                                              thumbnailData: photo.thumbnailData,
                                              takenAt: photo.meta.takenAt,
                                              latitude: photo.meta.latitude,
                                              longitude: photo.meta.longitude,
                                              sortOrder: 0))
                }
            }
        case .edit(let shop):
            shop.name = name
            shop.address = draft.address
            shop.memo = draft.memo
            shop.tags = tags
            shop.updatedAt = .now
        }
        try? context.save()

        if let onSaved {
            onSaved()
        } else {
            dismiss()
        }
    }

    private func deleteShop() {
        guard case .edit(let shop) = mode else { return }
        context.delete(shop)
        try? context.save()
        dismiss()
    }
}

// タグの選択（タップで選択/解除）
struct TagChipsView: View {
    let tags: [Tag]
    @Binding var selected: Set<UUID>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(tags.filter { $0.isPreset || selected.contains($0.id) }) { tag in
                let isOn = selected.contains(tag.id)
                Button {
                    if isOn { selected.remove(tag.id) } else { selected.insert(tag.id) }
                } label: {
                    Text(tag.name)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
