import Foundation
import FirebaseFirestore
import CoreLocation // 좌표(CLLocationCoordinate2D) 사용을 위해 필요

class FavoritesManager: ObservableObject {
    // UI에 연동될 즐겨찾기 목록
    @Published var places: [TravelSpot] = []
    
    // Firestore 인스턴스
    private let db = Firestore.firestore()
    
    // ✅ [핵심] 현재 로그인한 사용자의 ID 가져오기
    // LoginViewModel에서 로그인 성공 시 저장했던 "user_uid"를 꺼내옵니다.
    private var currentUserID: String? {
        return UserDefaults.standard.string(forKey: "user_uid")
    }
    
    // MARK: - 1. 장소 추가 (Create)
    func addPlace(_ spot: TravelSpot) {
        // 로그인이 안 되어 있거나 비회원이면 저장 불가
        guard let uid = currentUserID else {
            print("🚫 비회원 상태입니다. 저장이 불가능합니다.")
            return
        }
        
        // 경로: users -> [사용자ID] -> favorites -> [장소ID]
        // 이렇게 하면 사용자마다 자신만의 즐겨찾기 폴더를 갖게 됩니다.
        let docRef = db.collection("users").document(uid).collection("favorites").document(spot.placeID)
        
        // 저장할 데이터 딕셔너리 생성
        let data: [String: Any] = [
            "placeID": spot.placeID,
            "name": spot.name,
            "address": spot.address,
            "latitude": spot.coordinate.latitude,
            "longitude": spot.coordinate.longitude,
            "timestamp": FieldValue.serverTimestamp() // 정렬을 위한 저장 시간
        ]
        
        // DB에 쓰기
        docRef.setData(data) { error in
            if let error = error {
                print("❌ 저장 실패: \(error.localizedDescription)")
            } else {
                print("✅ 장소 저장 성공: \(spot.name)")
                self.fetchPlaces() // 목록 갱신
            }
        }
    }
    
    // MARK: - 2. 장소 삭제 (Delete)
    func removePlace(_ spot: TravelSpot) {
        guard let uid = currentUserID else { return }
        
        // 해당 경로의 문서 삭제
        db.collection("users").document(uid).collection("favorites").document(spot.placeID).delete { error in
            if let error = error {
                print("❌ 삭제 실패: \(error.localizedDescription)")
            } else {
                print("🗑️ 삭제 완료: \(spot.name)")
                self.fetchPlaces() // 목록 갱신
            }
        }
    }
    
    // MARK: - 3. 장소 불러오기 (Read)
    func fetchPlaces() {
        // 로그인 ID가 없으면 목록을 비우고 리턴 (비회원 처리)
        guard let uid = currentUserID else {
            self.places = []
            return
        }
        
        // 내 ID 폴더의 데이터만 가져옴 (최신순 정렬)
        db.collection("users").document(uid).collection("favorites")
            .order(by: "timestamp", descending: true)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("❌ 데이터 로드 실패: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                DispatchQueue.main.async {
                    // DB 데이터를 TravelSpot 객체로 변환
                    self?.places = documents.compactMap { doc -> TravelSpot? in
                        let data = doc.data()
                        
                        let id = data["placeID"] as? String ?? UUID().uuidString
                        let name = data["name"] as? String ?? "이름 없음"
                        let address = data["address"] as? String ?? ""
                        let lat = data["latitude"] as? Double ?? 0.0
                        let lng = data["longitude"] as? Double ?? 0.0
                        
                        return TravelSpot(
                            placeID: id,
                            name: name,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            address: address
                        )
                    }
                }
            }
    }
    
    // MARK: - 4. 로그아웃 시 데이터 정리 (Helper)
    // 로그아웃 버튼을 누를 때 이 함수를 호출해주세요.
    func clearUserData() {
        // 저장된 ID 삭제
        UserDefaults.standard.removeObject(forKey: "user_uid")
        // 화면에 보여지는 목록 초기화
        self.places = []
        print("🔒 로그아웃 처리 완료 (로컬 데이터 초기화)")
    }
}
