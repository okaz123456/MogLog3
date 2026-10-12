import SwiftUI
import PhotosUI

// 写真から店を登録（S-04）
struct PhotoRegisterView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: ProcessedPhoto?
    @State private var isProcessing = false
    @State private var loadError = ""
    @State private var model = ShopSearchModel()
    @State private var nameKeyword = ""
    @State private var viewerItem: ViewerItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "写真を選ぶ" : "別の写真を選ぶ", systemImage: "photo")
                    }
                    if isProcessing {
                        ProgressView("写真を読み込み中…")
                    }
                    if !loadError.isEmpty {
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let photo {
                        HStack(spacing: 12) {
                            ThumbnailImage(data: photo.thumbnailData, size: 72)
                                .onTapGesture {
                                    viewerItem = ViewerItem(data: photo.imageData)
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(takenText(photo))
                                    .font(.callout)
                                Text(photo.meta.latitude == nil ? "位置情報なし" : "位置情報あり")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("1. 写真")
                }

                if let photo {
                    if let lat = photo.meta.latitude, let lon = photo.meta.longitude {
                        Section {
                            if model.isSearching {
                                ProgressView()
                            } else if !model.message.isEmpty {
                                Text(model.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(model.candidates) { candidate in
                                NavigationLink {
                                    ShopEditView(mode: .new(draft(from: candidate)),
                                                 onSaved: { dismiss() })
                                } label: {
                                    CandidateRow(candidate: candidate,
                                                 distance: candidate.distance(fromLatitude: lat,
                                                                              longitude: lon))
                                }
                            }
                        } header: {
                            Text("2. お店の候補（撮影場所から近い順）")
                        }

                        Section {
                            HStack {
                                TextField("店名の一部", text: $nameKeyword)
                                    .onSubmit { searchByName(lat, lon) }
                                Button("検索") { searchByName(lat, lon) }
                                    .disabled(nameKeyword.trimmingCharacters(in: .whitespaces).isEmpty
                                              || model.isSearching)
                            }
                        } header: {
                            Text("候補にない場合：店名で探す（撮影場所の周辺）")
                        }
                    } else {
                        Section {
                            Text("この写真には位置情報がありません。下の「手入力」で登録してください。")
                                .font(.callout)
                        }
                    }

                    Section {
                        NavigationLink {
                            ShopEditView(mode: .new(manualDraft()), onSaved: { dismiss() })
                        } label: {
                            Label("候補にない（手入力で登録）", systemImage: "square.and.pencil")
                        }
                    } footer: {
                        Text("手入力の場合も、撮影場所の座標・撮影日・写真が登録に使われます。")
                    }
                }
            }
            .navigationTitle("写真から登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .sheet(item: $viewerItem) { item in
                PhotoViewer(data: item.data)
            }
        }
    }

    private func takenText(_ photo: ProcessedPhoto) -> String {
        guard let taken = photo.meta.takenAt else { return "撮影日時：不明" }
        return "撮影日時：" + JPDate.dayTime(taken)
    }

    // 写真を読み込み、位置情報があれば周辺の店を検索
    private func load(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }
        loadError = ""
        model.candidates = []
        model.message = ""
        guard let data = try? await item.loadTransferable(type: Data.self),
              let processed = ImageTools.process(data) else {
            photo = nil
            loadError = "写真を読み込めませんでした"
            return
        }
        photo = processed
        if let lat = processed.meta.latitude, let lon = processed.meta.longitude {
            await model.searchNearby(latitude: lat, longitude: lon)
        }
    }

    private func searchByName(_ lat: Double, _ lon: Double) {
        let keyword = nameKeyword
        Task {
            await model.search(keyword: keyword, nearLatitude: lat, longitude: lon, foodOnly: false)
        }
    }

    // 候補から登録：店の座標は候補のもの、来店日と写真は写真から
    private func draft(from candidate: ShopCandidate) -> ShopDraft {
        var draft = ShopDraft(candidate: candidate)
        draft.source = .photo
        draft.prefillVisitDate = photo?.meta.takenAt ?? .now
        draft.prefillPhoto = photo
        return draft
    }

    // 手入力：店の座標は撮影場所（F-04）
    private func manualDraft() -> ShopDraft {
        var draft = ShopDraft(source: .photo)
        draft.latitude = photo?.meta.latitude
        draft.longitude = photo?.meta.longitude
        draft.prefillVisitDate = photo?.meta.takenAt ?? .now
        draft.prefillPhoto = photo
        return draft
    }
}

// 候補の行（店名・住所・距離）
struct CandidateRow: View {
    let candidate: ShopCandidate
    let distance: Double?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                Text(candidate.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let distance {
                Text(distanceText(distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func distanceText(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded()))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }
}
