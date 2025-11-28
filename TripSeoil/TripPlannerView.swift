import SwiftUI
import GoogleMaps
import GooglePlaces
import CoreLocation

// MARK: - 1. 데이터 모델
struct TravelSpot: Identifiable, Equatable {
    let id = UUID()
    let placeID: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    
    // [중요] PlaceID가 같으면 같은 장소로 취급
    static func == (lhs: TravelSpot, rhs: TravelSpot) -> Bool {
        return lhs.placeID == rhs.placeID
    }
}

// MARK: - 2. 경로 최적화 엔진 (로그 출력 기능 포함)
class RouteOptimizer {
    static func optimizeRoute(start: TravelSpot, destinations: [TravelSpot]) -> [TravelSpot] {
        print("\n----------- 🔄 동선 최적화 시작 -----------")
        print("🚩 출발지: \(start.name)")
        
        var unvisited = destinations
        var current = start
        var optimizedPath: [TravelSpot] = []
        
        // Nearest Neighbor 알고리즘 (가장 가까운 곳부터 방문)
        while !unvisited.isEmpty {
            // 현재 위치(current)에서 가장 가까운 장소 찾기
            let nearestIndex = unvisited.indices.min(by: { indexA, indexB in
                let spotA = unvisited[indexA]
                let spotB = unvisited[indexB]
                
                let distA = distance(from: current.coordinate, to: spotA.coordinate)
                let distB = distance(from: current.coordinate, to: spotB.coordinate)
                
                return distA < distB
            })
            
            if let index = nearestIndex {
                let nextSpot = unvisited.remove(at: index)
                let dist = distance(from: current.coordinate, to: nextSpot.coordinate)
                
                // 콘솔에 거리 정보 출력 (디버깅용)
                print("➡️ 다음 목적지: \(nextSpot.name) (거리: \(String(format: "%.2f", dist/1000))km)")
                
                optimizedPath.append(nextSpot)
                current = nextSpot // 기준점 이동
            }
        }
        
        print("----------- ✅ 최적화 완료 (총 \(optimizedPath.count)곳) -----------\n")
        return optimizedPath
    }
    
    // 좌표 간 직선 거리 계산 (CLLocation 이용)
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let locationA = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let locationB = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return locationA.distance(from: locationB) // 미터(m) 단위 반환
    }
}

// MARK: - 3. Places API 매니저 (장소 검색)
class PlacesManager: NSObject, ObservableObject {
    private let client = GMSPlacesClient.shared()
    
    func searchPlaces(query: String, completion: @escaping (TravelSpot?) -> Void) {
        let filter = GMSAutocompleteFilter()
        
        client.findAutocompletePredictions(fromQuery: query, filter: filter, sessionToken: nil) { (results, error) in
            guard let result = results?.first else {
                print("검색 결과 없음")
                completion(nil)
                return
            }
            
            // [중요] 좌표(.coordinate)와 ID(.placeID)를 반드시 요청해야 함
            let fields: GMSPlaceField = [.name, .coordinate, .formattedAddress, .placeID]
            
            self.client.fetchPlace(fromPlaceID: result.placeID, placeFields: fields, sessionToken: nil) { (place, error) in
                guard let place = place, let name = place.name else {
                    completion(nil)
                    return
                }
                
                let spot = TravelSpot(
                    placeID: place.placeID ?? result.placeID,
                    name: name,
                    coordinate: place.coordinate,
                    address: place.formattedAddress ?? ""
                )
                completion(spot)
            }
        }
    }
}

// MARK: - 4. Directions API 매니저 (도로 경로 그리기)
class DirectionsManager: ObservableObject {
    // [적용됨] 사용자 API 키
    private let apiKey = "AIzaSyAyWUuq6RwQ-qAo4KOgVE8Vk4-cBspN_bY"
    
    func fetchRoute(from start: TravelSpot, waypoints: [TravelSpot], completion: @escaping (String?) -> Void) {
        guard !waypoints.isEmpty else {
            completion(nil)
            return
        }
        
        // 1. 좌표 문자열 변환
        let origin = "\(start.coordinate.latitude),\(start.coordinate.longitude)"
        let destination = "\(waypoints.last!.coordinate.latitude),\(waypoints.last!.coordinate.longitude)"
        
        // 2. 경유지(Waypoints) 처리: 마지막 목적지를 제외한 중간 지점들
        var waypointsString = ""
        if waypoints.count > 1 {
            let middlePoints = waypoints.dropLast()
            let coords = middlePoints.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }
            waypointsString = "&waypoints=" + coords.joined(separator: "|")
        }
        
        // 3. URL 생성 (driving 모드)
        let urlString = "https://maps.googleapis.com/maps/api/directions/json?origin=\(origin)&destination=\(destination)\(waypointsString)&mode=driving&key=\(apiKey)"
        
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            completion(nil)
            return
        }
        
        print("🚗 경로 요청 URL: \(urlString)")
        
        // 4. 요청 및 파싱
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("경로 요청 실패: \(error?.localizedDescription ?? "")")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    // API 상태 확인
                    if let status = json["status"] as? String, status != "OK" {
                        print("❌ Directions API 오류: \(status)")
                        if let errorMessage = json["error_message"] as? String {
                            print("상세 메시지: \(errorMessage)")
                        }
                        completion(nil)
                        return
                    }
                    
                    if let routes = json["routes"] as? [[String: Any]],
                       let route = routes.first,
                       let overviewPolyline = route["overview_polyline"] as? [String: Any],
                       let points = overviewPolyline["points"] as? String {
                        
                        // 성공: 암호화된 경로 문자열 반환
                        DispatchQueue.main.async {
                            completion(points)
                        }
                        return
                    }
                }
                print("JSON 파싱 실패 또는 경로 없음")
                completion(nil)
            } catch {
                print("JSON 오류: \(error)")
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - 5. 메인 뷰 (UI)
struct TripPlannerView: View {
    @StateObject private var placesManager = PlacesManager()
    @EnvironmentObject var favoriteStore: FavoriteStore // 즐겨찾기 저장소
    
    // --- 입력 상태 ---
    @State private var targetRegion: String = "서울 성동구"
    @State private var searchQuery: String = ""
    
    // --- 여행 데이터 ---
    @State private var startPoint: TravelSpot?
    @State private var bucketList: [TravelSpot] = []
    
    // --- UI 상태 ---
    @State private var showMap = false
    @State private var isOptimized = false
    @State private var showFavoritesSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // [섹션 1] 설정 영역
                VStack(spacing: 16) {
                    // 1. 지역 설정
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.gray)
                        TextField("지역 입력 (예: 부산 해운대구)", text: $targetRegion)
                            .textFieldStyle(.plain)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    // 2. 출발지 설정 (필수)
                    HStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.blue)
                        if let start = startPoint {
                            Text("출발: \(start.name)")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Spacer()
                            Button { startPoint = nil; isOptimized = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        } else {
                            TextField("출발지 검색 (예: 성수역)", text: $searchQuery)
                                .onSubmit { searchStartPoint() }
                            Button("설정") { searchStartPoint() }
                                .font(.caption)
                                .padding(6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    
                    // 3. 즐겨찾기 불러오기 버튼 (출발지 설정 후 표시)
                    if startPoint != nil {
                        Button(action: { showFavoritesSheet = true }) {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                                Text("즐겨찾기에서 장소 불러오기")
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                        }
                    }
                }
                .padding()
                .background(Color.white)
                
                // [섹션 2] 리스트 영역
                List {
                    if bucketList.isEmpty {
                        VStack(spacing: 10) {
                            Text(startPoint == nil ? "먼저 출발지를 설정해주세요." : "즐겨찾기한 장소를 불러와주세요!")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            if startPoint != nil {
                                Text("(추천 탭에서 ❤️를 눌러 장소를 담으세요)")
                                    .font(.caption)
                                    .foregroundColor(.blue.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                        .listRowSeparator(.hidden)
                    } else {
                        Section(header: Text("여행 코스 (\(bucketList.count)곳)")) {
                            ForEach(Array(bucketList.enumerated()), id: \.element.id) { index, spot in
                                HStack {
                                    if isOptimized {
                                        ZStack {
                                            Circle().fill(Color.blue)
                                                .frame(width: 24, height: 24)
                                            Text("\(index + 1)")
                                                .font(.caption).bold()
                                                .foregroundColor(.white)
                                        }
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.gray)
                                    }
                                    
                                    VStack(alignment: .leading) {
                                        Text(spot.name).font(.headline)
                                        Text(spot.address).font(.caption).foregroundColor(.gray)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                bucketList.remove(atOffsets: indexSet)
                                isOptimized = false
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
                // [섹션 3] 하단 액션 버튼
                HStack(spacing: 12) {
                    // 최적화 버튼
                    Button(action: optimizePath) {
                        HStack {
                            Image(systemName: "arrow.triangle.swap")
                            Text("최소 동선 정렬")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background((startPoint == nil || bucketList.isEmpty) ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(startPoint == nil || bucketList.isEmpty)
                    
                    // 지도 보기 버튼
                    Button(action: { showMap = true }) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .padding()
                            .background((startPoint == nil) ? Color.gray : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(startPoint == nil)
                }
                .padding()
            }
            .navigationTitle("여행 코스 짜기")
            // 즐겨찾기 시트
            .sheet(isPresented: $showFavoritesSheet) {
                VStack {
                    Text("나의 찜 목록 ❤️").font(.headline).padding()
                    
                    if favoriteStore.favorites.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "heart.slash")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("즐겨찾기한 장소가 없습니다.")
                            Text("추천 탭에서 마음에 드는 곳을 찜해보세요!")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(favoriteStore.favorites) { place in
                                Button(action: {
                                    addFromFavorite(place)
                                }) {
                                    HStack {
                                        let isAdded = bucketList.contains(where: { $0.placeID == place.id })
                                        
                                        Image(systemName: "heart.fill").foregroundColor(.red)
                                        VStack(alignment: .leading) {
                                            Text(place.name).foregroundColor(.primary)
                                            Text(place.address).font(.caption).foregroundColor(.gray)
                                        }
                                        Spacer()
                                        if isAdded {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                        } else {
                                            Image(systemName: "plus.circle").foregroundColor(.blue)
                                        }
                                    }
                                }
                                .disabled(bucketList.contains(where: { $0.placeID == place.id }))
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showMap) {
                if let start = startPoint {
                    RouteResultMapView(startPoint: start, waypoints: bucketList)
                }
            }
        }
    }
    
    // MARK: - 로직 함수들
    func searchStartPoint() {
        guard !searchQuery.isEmpty else { return }
        let query = "\(targetRegion) \(searchQuery)"
        
        placesManager.searchPlaces(query: query) { spot in
            guard let spot = spot else { return }
            withAnimation {
                self.startPoint = spot
                self.isOptimized = false
            }
            self.searchQuery = ""
        }
    }
    
    func addFromFavorite(_ fav: FavoritePlace) {
        let spot = TravelSpot(
            placeID: fav.id,
            name: fav.name,
            coordinate: CLLocationCoordinate2D(latitude: fav.latitude, longitude: fav.longitude),
            address: fav.address
        )
        
        if !bucketList.contains(where: { $0.placeID == spot.placeID }) {
            withAnimation {
                bucketList.append(spot)
                isOptimized = false
            }
        }
    }
    
    func optimizePath() {
        guard let start = startPoint else { return }
        let sortedList = RouteOptimizer.optimizeRoute(start: start, destinations: bucketList)
        withAnimation(.spring()) {
            self.bucketList = sortedList
            self.isOptimized = true
        }
    }
}

// MARK: - 6. 결과 지도 뷰 (로딩 상태 관리 포함)
struct RouteResultMapView: View {
    let startPoint: TravelSpot
    let waypoints: [TravelSpot]
    @Environment(\.dismiss) var dismiss
    
    @State private var encodedPath: String?
    @StateObject private var directionsManager = DirectionsManager()
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 지도
            TripGoogleMapView(start: startPoint, waypoints: waypoints, encodedPath: encodedPath)
                .edgesIgnoringSafeArea(.all)
            
            // 닫기 버튼
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .padding()
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .padding()
            
            // 상태 표시
            if isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView("도로 경로 계산 중...")
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                        Spacer()
                    }
                    Spacer()
                }
                .background(Color.black.opacity(0.2))
            } else if let error = errorMessage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("도로 경로를 불러올 수 없습니다.")
                                .font(.headline)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            Text("(직선 경로로 표시됩니다)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        Spacer()
                    }
                    Spacer()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { errorMessage = nil }
                    }
                }
            }
        }
        .onAppear {
            // 경로 요청 시작
            directionsManager.fetchRoute(from: startPoint, waypoints: waypoints) { pathString in
                self.isLoading = false
                
                if let path = pathString {
                    self.encodedPath = path
                } else {
                    self.errorMessage = "Google API에서 경로를 찾지 못했습니다.\n(API 키 할당량을 확인해주세요)"
                }
            }
        }
    }
}

// MARK: - 7. Google Maps Wrapper
struct TripGoogleMapView: UIViewRepresentable {
    let start: TravelSpot
    let waypoints: [TravelSpot]
    let encodedPath: String?
    
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: start.coordinate.latitude, longitude: start.coordinate.longitude, zoom: 14)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.clear()
        
        // 도로 경로 그리기
        if let pathString = encodedPath, let path = GMSPath(fromEncodedPath: pathString) {
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 5
            polyline.strokeColor = .systemBlue
            polyline.map = mapView
        } else {
            // 로딩 중/실패 시 직선 점선
            let path = GMSMutablePath()
            path.add(start.coordinate)
            for spot in waypoints { path.add(spot.coordinate) }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 2
            polyline.strokeColor = .lightGray
            polyline.map = mapView
        }
        
        // 마커 찍기
        let startMarker = GMSMarker(position: start.coordinate)
        startMarker.title = "출발: \(start.name)"
        startMarker.icon = GMSMarker.markerImage(with: .blue)
        startMarker.map = mapView
        
        for (index, spot) in waypoints.enumerated() {
            let marker = GMSMarker(position: spot.coordinate)
            marker.title = "\(index + 1). \(spot.name)"
            marker.icon = GMSMarker.markerImage(with: .red)
            marker.map = mapView
        }
        
        // 카메라 조정
        var bounds = GMSCoordinateBounds()
        bounds = bounds.includingCoordinate(start.coordinate)
        for spot in waypoints { bounds = bounds.includingCoordinate(spot.coordinate) }
        
        if let pathString = encodedPath, let path = GMSPath(fromEncodedPath: pathString) {
            for i in 0..<path.count() {
                bounds = bounds.includingCoordinate(path.coordinate(at: i))
            }
        }
        
        let update = GMSCameraUpdate.fit(bounds, withPadding: 60.0)
        mapView.animate(with: update)
    }
}

// MARK: - 8. Preview
struct TripPlannerView_Previews: PreviewProvider {
    static var previews: some View {
        TripPlannerView()
            .environmentObject(FavoriteStore())
    }
}
