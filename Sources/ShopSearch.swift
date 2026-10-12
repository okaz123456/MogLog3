import Foundation
import Observation
import MapKit

// 検索結果の候補（保存前の一時データ）
struct ShopCandidate: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let phone: String?
    let url: String?

    // 指定地点からの距離（m）
    func distance(fromLatitude lat: Double, longitude lon: Double) -> Double {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: lat, longitude: lon)
        return here.distance(from: there)
    }
}

@MainActor
@Observable
final class ShopSearchModel {
    var candidates: [ShopCandidate] = []
    var message = ""
    var isSearching = false

    static let foodFilter = MKPointOfInterestFilter(including: [
        .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife
    ])

    // キーワード検索。座標を指定すると、その周辺に限定して近い順に並べる
    func search(keyword: String,
                nearLatitude lat: Double? = nil,
                longitude lon: Double? = nil,
                regionMeters: Double = 2000,
                foodOnly: Bool = true) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .pointOfInterest
        if foodOnly {
            request.pointOfInterestFilter = Self.foodFilter
        }
        if let lat, let lon {
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            request.region = MKCoordinateRegion(center: center,
                                                latitudinalMeters: regionMeters,
                                                longitudinalMeters: regionMeters)
            request.regionPriority = .required   // 指定範囲内の結果に限定
        }
        await run(MKLocalSearch(request: request))
        if let lat, let lon, !candidates.isEmpty {
            sortByDistance(lat, lon)
            message = "\(candidates.count)件（撮影場所の周辺・店名で検索）"
        }
    }

    // 座標の周辺検索：見つからなければ範囲を広げる（D-07）
    func searchNearby(latitude: Double, longitude: Double) async {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        for radius in [150.0, 400.0, 1000.0] {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
            request.pointOfInterestFilter = Self.foodFilter
            await run(MKLocalSearch(request: request))
            if !candidates.isEmpty {
                sortByDistance(latitude, longitude)
                message = "\(candidates.count)件（半径\(Int(radius))m以内）"
                return
            }
        }
        message = "周辺で見つかりませんでした。店名で探すか、手入力してください"
    }

    private func sortByDistance(_ lat: Double, _ lon: Double) {
        candidates.sort { first, second in
            let d1: Double = first.distance(fromLatitude: lat, longitude: lon)
            let d2: Double = second.distance(fromLatitude: lat, longitude: lon)
            return d1 < d2
        }
    }

    private func run(_ search: MKLocalSearch) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await search.start()
            candidates = response.mapItems.map { Self.makeCandidate($0) }
            message = candidates.isEmpty ? "見つかりませんでした" : "\(candidates.count)件"
        } catch let error as MKError where error.code == .placemarkNotFound {
            candidates = []
            message = "見つかりませんでした"
        } catch {
            candidates = []
            message = "エラー：\(error.localizedDescription)"
        }
    }

    // iOS 26の住所API（I-05）
    static func makeCandidate(_ item: MKMapItem) -> ShopCandidate {
        ShopCandidate(
            name: item.name ?? "（名称なし）",
            address: item.address?.fullAddress ?? "",
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            phone: item.phoneNumber,
            url: item.url?.absoluteString
        )
    }
}
