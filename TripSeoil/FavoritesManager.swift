import FirebaseFirestore

class FavoritesManager: ObservableObject {
    @Published var savedPlaces: [TravelSpot] = []
    private let db = Firestore.firestore()
    
    // 저장하기 (Create)
    func savePlace(_ spot: TravelSpot) {
        let data: [String: Any] = [
            "placeID": spot.placeID,
            "name": spot.name,
            "latitude": spot.coordinate.latitude,
            "longitude": spot.coordinate.longitude,
            "address": spot.address,
            "timestamp": Timestamp() // 저장 시간
        ]
        
        // 'users' 컬렉션 -> '내아이디' 문서 -> 'favorites' 컬렉션에 저장
        db.collection("users").document("myDeviceID").collection("favorites").document(spot.placeID).setData(data) { error in
            if error == nil {
                print("저장 완료!")
                self.fetchFavorites() // 저장 후 목록 갱신
            }
        }
    }
    
    // 불러오기 (Read)
    func fetchFavorites() {
        db.collection("users").document("myDeviceID").collection("favorites")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self.savedPlaces = documents.compactMap { doc -> TravelSpot? in
                    let data = doc.data()
                    guard let name = data["name"] as? String,
                          let lat = data["latitude"] as? Double,
                          let lng = data["longitude"] as? Double,
                          let address = data["address"] as? String else { return nil }
                    
                    return TravelSpot(
                        placeID: doc.documentID,
                        name: name,
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        address: address
                    )
                }
            }
    }
    
    // 삭제하기 (Delete) - [휴지통 버튼 연결]
    func removePlace(_ placeID: String) {
        db.collection("users").document("myDeviceID").collection("favorites").document(placeID).delete() { _ in
            self.fetchFavorites()
        }
    }
}
