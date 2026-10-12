import SwiftUI
import UIKit

// サムネイル（正方形に切り抜き）
struct ThumbnailImage: View {
    let data: Data
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)   // 画像として読めないデータ（サンプル等）
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// 拡大表示する写真の受け渡し用（複数枚と、最初に表示する位置）
struct ViewerItem: Identifiable {
    let id = UUID()
    let images: [Data]
    let index: Int

    init(data: Data) {
        self.images = [data]
        self.index = 0
    }

    init(images: [Data], index: Int) {
        self.images = images
        self.index = min(max(index, 0), max(images.count - 1, 0))
    }

    var data: Data { images[index] }
}

// 拡大表示（1枚）：従来の呼び出し方のまま使えるようにする
struct PhotoViewer: View {
    let data: Data

    var body: some View {
        PhotoPagerView(images: [data], startIndex: 0)
    }
}

// 拡大表示（複数枚）：左右スワイプで切り替え、ピンチで拡大（I-20、I-21）
struct PhotoPagerView: View {
    @Environment(\.dismiss) private var dismiss
    let images: [Data]
    @State private var index: Int

    init(images: [Data], startIndex: Int) {
        self.images = images
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { item in
                    ZoomablePhoto(data: item.element)
                        .tag(item.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if images.count > 1 {
                        Text("\(index + 1) / \(images.count)")
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// 1枚の写真の拡大操作：ピンチで拡大縮小、ダブルタップで拡大／元に戻す、拡大中はドラッグで移動
struct ZoomablePhoto: View {
    let data: Data

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .gesture(magnifyGesture)
                        // 拡大中だけドラッグで移動（等倍のときは左右スワイプで写真を切り替える）
                        .highPriorityGesture(dragGesture, including: scale > 1 ? .all : .subviews)
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ContentUnavailableView("表示できません", systemImage: "photo")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .background(Color.black)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale: CGFloat = lastScale * value.magnification
                scale = min(max(newScale, 1), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { reset() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if scale > 1 {
                reset()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
