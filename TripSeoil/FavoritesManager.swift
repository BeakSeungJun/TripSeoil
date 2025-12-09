import Foundation
import FirebaseFirestore
import CoreLocation

class FavoritesManager: ObservableObject {
    @Published var savedPlaces: [TravelSpot] = []
    private let db = Firestore.firestore()
    
    // 내 기기 고유 ID (회원가입 없이 기기별로 저장하기 위함)
    // 실제 앱에서는 로그인한 User UID를 쓰는 것이 좋습니다.
    private let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown_device"
    
    // 1. 저장하기 (Create)
    func addPlace(_ spot: TravelSpot) {
        let data: [String: Any] = [
            "placeID": spot.placeID,
            "name": spot.name,
            "latitude": spot.coordinate.latitude,
            "longitude": spot.coordinate.longitude,
            "address": spot.address,
            "timestamp": Timestamp() // 정렬을 위해 저장 시간 기록
        ]
        
        db.collection("users").document(deviceID).collection("favorites").document(spot.placeID).setData(data) { error in
            if let error = error {
                print("저장 실패: \(error.localizedDescription)")
            } else {
                print("Firebase 저장 성공!")
                self.fetchPlaces() // 저장 후 목록 새로고침
            }
        }
    }
    
    // 2. 불러오기 (Read)
    func fetchPlaces() {
        db.collection("users").document(deviceID).collection("favorites")
            .order(by: "timestamp", descending: true) // 최신순 정렬
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("문서 없음")
                    return
                }
                
                DispatchQueue.main.async {
                    self.savedPlaces = documents.compactMap { doc -> TravelSpot? in
                        let data = doc.data()
                        guard let name = data["name"] as? String,
                              let address = data["address"] as? String,
                              let lat = data["latitude"] as? Double,
                              let lng = data["longitude"] as? Double else { return nil }
                        
                        return TravelSpot(
                            placeID: doc.documentID,
                            name: name,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            address: address
                        )
                    }
                }
            }
    }
    
    // 3. 삭제하기 (Delete)
    func removePlace(_ spot: TravelSpot) {
        db.collection("users").document(deviceID).collection("favorites").document(spot.placeID).delete() { error in
            if error == nil {
                self.fetchPlaces() // 삭제 후 목록 새로고침
            }
        }
    }
}
