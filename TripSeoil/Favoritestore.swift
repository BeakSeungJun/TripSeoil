import SwiftUI
import CoreLocation

// 즐겨찾기 데이터 모델
struct FavoritePlace: Identifiable, Codable, Equatable {
    var id: String // 장소 ID (Google Place ID)
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

// 앱 전체에서 공유할 저장소 클래스
class FavoriteStore: ObservableObject {
    @Published var favorites: [FavoritePlace] = []
    
    // 즐겨찾기 추가/삭제 토글 함수
    func toggleFavorite(id: String, name: String, address: String, coordinate: CLLocationCoordinate2D) {
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            // 이미 있으면 삭제
            favorites.remove(at: index)
        } else {
            // 없으면 추가
            let newPlace = FavoritePlace(
                id: id,
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            favorites.append(newPlace)
        }
    }
    
    // 특정 장소가 즐겨찾기인지 확인
    func isFavorite(_ id: String) -> Bool {
        return favorites.contains(where: { $0.id == id })
    }
}
