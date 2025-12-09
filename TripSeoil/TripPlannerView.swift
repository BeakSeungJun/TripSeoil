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
    
    static func == (lhs: TravelSpot, rhs: TravelSpot) -> Bool {
        return lhs.placeID == rhs.placeID
    }
}

struct ColoredRouteSegment: Identifiable {
    let id = UUID()
    let encodedPath: String
    let color: UIColor
    let isWalking: Bool
}

struct RouteStep: Identifiable {
    let id = UUID()
    let instruction: String
    let detail: String
    let duration: String
    let transportType: String
    let lineName: String?
    let lineColor: String?
}

enum TransportMode: String, CaseIterable, Identifiable {
    case driving = "driving"
    case transit = "transit"
    case walking = "walking"
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .driving: return "차량"
        case .transit: return "대중교통"
        case .walking: return "도보"
        }
    }
    
    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .transit: return "bus.fill"
        case .walking: return "figure.walk"
        }
    }
}

// MARK: - 2. 경로 최적화 엔진
class RouteOptimizer {
    static func optimizeRoute(start: TravelSpot, destinations: [TravelSpot]) -> [TravelSpot] {
        var unvisited = destinations
        var current = start
        var optimizedPath: [TravelSpot] = []
        
        while !unvisited.isEmpty {
            let nearestIndex = unvisited.indices.min(by: { indexA, indexB in
                let distA = distance(from: current.coordinate, to: unvisited[indexA].coordinate)
                let distB = distance(from: current.coordinate, to: unvisited[indexB].coordinate)
                return distA < distB
            })
            
            if let index = nearestIndex {
                let nextSpot = unvisited.remove(at: index)
                optimizedPath.append(nextSpot)
                current = nextSpot
            }
        }
        return optimizedPath
    }
    
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let locationA = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let locationB = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return locationA.distance(from: locationB)
    }
}

// MARK: - 3. Places API 매니저
class PlacesManager: NSObject, ObservableObject {
    private let client = GMSPlacesClient.shared()
    
    func searchPlaces(query: String, completion: @escaping (TravelSpot?) -> Void) {
        let filter = GMSAutocompleteFilter()
        
        client.findAutocompletePredictions(fromQuery: query, filter: filter, sessionToken: nil) { (results, error) in
            guard let result = results?.first else {
                completion(nil)
                return
            }
            
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

// MARK: - 4. Directions API 매니저 (구간별 상세 파싱)
class DirectionsManager: ObservableObject {
    private let apiKey = "AIzaSyAyWUuq6RwQ-qAo4KOgVE8Vk4-cBspN_bY"
    
    func fetchRoute(from start: TravelSpot, waypoints: [TravelSpot], mode: TransportMode, completion: @escaping ([ColoredRouteSegment]?, String?, String?, [RouteStep]?) -> Void) {
        
        let allSpots = [start] + waypoints
        guard allSpots.count >= 2 else { completion(nil, nil, nil, nil); return }
        
        let group = DispatchGroup()
        
        var segmentsMap: [Int: [ColoredRouteSegment]] = [:]
        var stepsMap: [Int: [RouteStep]] = [:]
        
        var totalDuration = 0
        var totalDistance = 0
        var hasError = false
        
        for i in 0..<(allSpots.count - 1) {
            let originSpot = allSpots[i]
            let destSpot = allSpots[i+1]
            
            group.enter()
            
            // 좌표 기반 요청 (범용성)
            let origin = "\(originSpot.coordinate.latitude),\(originSpot.coordinate.longitude)"
            let destination = "\(destSpot.coordinate.latitude),\(destSpot.coordinate.longitude)"
            
            let urlString = "https://maps.googleapis.com/maps/api/directions/json?origin=\(origin)&destination=\(destination)&mode=\(mode.rawValue)&language=ko&key=\(apiKey)"
            
            guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
                group.leave(); continue
            }
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    if let status = json["status"] as? String, status != "OK" {
                        hasError = true // 실패 플래그
                        return
                    }
                    
                    if let routes = json["routes"] as? [[String: Any]], let route = routes.first {
                        DispatchQueue.main.async(flags: .barrier) {
                            var segmentColorParts: [ColoredRouteSegment] = []
                            var segmentSteps: [RouteStep] = []
                            
                            if let legs = route["legs"] as? [[String: Any]] {
                                for leg in legs {
                                    if let dur = leg["duration"] as? [String: Any], let val = dur["value"] as? Int { totalDuration += val }
                                    if let dis = leg["distance"] as? [String: Any], let val = dis["value"] as? Int { totalDistance += val }
                                    
                                    if let steps = leg["steps"] as? [[String: Any]] {
                                        for step in steps {
                                            segmentSteps.append(self.parseStep(step))
                                            
                                            if let polylineObj = step["polyline"] as? [String: Any],
                                               let encodedPath = polylineObj["points"] as? String {
                                                
                                                var strokeColor: UIColor = .gray
                                                var isWalk = false
                                                
                                                if let transitDetails = step["transit_details"] as? [String: Any],
                                                   let line = transitDetails["line"] as? [String: Any],
                                                   let colorHex = line["color"] as? String {
                                                    strokeColor = UIColor(hexString: colorHex)
                                                } else {
                                                    isWalk = true
                                                    strokeColor = .lightGray
                                                }
                                                
                                                if mode == .driving { strokeColor = .systemBlue; isWalk = false }
                                                if mode == .walking { strokeColor = .systemOrange; isWalk = true }
                                                
                                                segmentColorParts.append(ColoredRouteSegment(encodedPath: encodedPath, color: strokeColor, isWalking: isWalk))
                                            }
                                        }
                                    }
                                }
                            }
                            segmentsMap[i] = segmentColorParts
                            stepsMap[i] = segmentSteps
                        }
                    }
                }
            }.resume()
        }
        
        group.notify(queue: .main) {
            // 하나라도 실패했거나 데이터가 없으면 nil 반환 -> 뷰에서 딥링크 버튼 표시
            if hasError || segmentsMap.isEmpty {
                completion(nil, nil, nil, nil)
                return
            }
            
            var finalColoredSegments: [ColoredRouteSegment] = []
            var finalSteps: [RouteStep] = []
            
            for i in 0..<(allSpots.count - 1) {
                if let parts = segmentsMap[i] { finalColoredSegments.append(contentsOf: parts) }
                if let stps = stepsMap[i] { finalSteps.append(contentsOf: stps) }
            }
            
            let timeString = self.formatTime(seconds: totalDuration)
            let distanceString = String(format: "%.1f km", Double(totalDistance) / 1000.0)
            
            completion(finalColoredSegments, timeString, distanceString, finalSteps)
        }
    }
    
    private func parseStep(_ step: [String: Any]) -> RouteStep {
        let htmlInstruction = step["html_instructions"] as? String ?? ""
        let instruction = htmlInstruction.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        
        let duration = (step["duration"] as? [String: Any])?["text"] as? String ?? ""
        let travelMode = step["travel_mode"] as? String ?? "WALKING"
        
        var lineName: String? = nil
        var lineColor: String? = nil
        var detailText = ""
        
        if travelMode == "TRANSIT", let transitDetails = step["transit_details"] as? [String: Any] {
            if let line = transitDetails["line"] as? [String: Any] {
                lineName = (line["short_name"] as? String) ?? (line["name"] as? String)
                lineColor = line["color"] as? String
            }
            let departure = (transitDetails["departure_stop"] as? [String: Any])?["name"] as? String ?? ""
            let arrival = (transitDetails["arrival_stop"] as? [String: Any])?["name"] as? String ?? ""
            let numStops = transitDetails["num_stops"] as? Int ?? 0
            detailText = "\(departure) → \(arrival) (\(numStops)개 역)"
        } else {
            detailText = (step["distance"] as? [String: Any])?["text"] as? String ?? ""
        }
        
        return RouteStep(
            instruction: instruction,
            detail: detailText,
            duration: duration,
            transportType: travelMode,
            lineName: lineName,
            lineColor: lineColor
        )
    }
    
    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"
    }
}

// MARK: - 5. 메인 뷰 (UI)
struct TripPlannerView: View {
    @StateObject private var placesManager = PlacesManager()
    @EnvironmentObject var favoriteStore: FavoriteStore
    
    @State private var targetRegion: String = "Seoul" // 기본값 서울
    @State private var searchQuery: String = ""
    @State private var startPoint: TravelSpot?
    @State private var bucketList: [TravelSpot] = []
    
    @State private var showMap = false
    @State private var isOptimized = false
    @State private var showFavoritesSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 설정
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "mappin.and.ellipse").foregroundColor(.gray)
                        TextField("지역 입력 (예: Seoul)", text: $targetRegion).textFieldStyle(.plain)
                    }
                    .padding().background(Color.gray.opacity(0.1)).cornerRadius(10)
                    
                    HStack {
                        Image(systemName: "car.fill").foregroundColor(.blue)
                        if let start = startPoint {
                            Text("출발: \(start.name)").fontWeight(.bold).foregroundColor(.blue)
                            Spacer()
                            Button { startPoint = nil; isOptimized = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        } else {
                            TextField("출발지 검색", text: $searchQuery).onSubmit { searchStartPoint() }
                            Button("설정") { searchStartPoint() }
                                .font(.caption).padding(6).background(Color.blue).foregroundColor(.white).cornerRadius(6)
                        }
                    }
                    .padding().background(Color.blue.opacity(0.05)).cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    
                    if startPoint != nil {
                        Button(action: { showFavoritesSheet = true }) {
                            HStack {
                                Image(systemName: "heart.fill").foregroundColor(.red)
                                Text("즐겨찾기에서 장소 불러오기").foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.gray)
                            }
                            .padding().background(Color.white).cornerRadius(10)
                            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                        }
                    }
                }
                .padding().background(Color.white)
                
                // 리스트
                List {
                    if bucketList.isEmpty {
                        VStack {
                            Text(startPoint == nil ? "먼저 출발지를 설정해주세요." : "장소를 추가해주세요!")
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .padding(.top, 20)
                    } else {
                        Section(header: Text("여행 코스 (\(bucketList.count)곳)")) {
                            ForEach(Array(bucketList.enumerated()), id: \.element.id) { index, spot in
                                HStack {
                                    if isOptimized {
                                        ZStack {
                                            Circle().fill(Color.blue).frame(width: 24, height: 24)
                                            Text("\(index + 1)").font(.caption).bold().foregroundColor(.white)
                                        }
                                    } else {
                                        Image(systemName: "circle").foregroundColor(.gray)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(spot.name).font(.headline)
                                        Text(spot.address).font(.caption).foregroundColor(.gray)
                                    }
                                    Spacer()
                                    // [삭제 버튼 복구됨]
                                    Button(action: { deleteSpot(at: index) }) {
                                        Image(systemName: "trash").foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
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
                
                // 버튼
                HStack(spacing: 12) {
                    Button(action: optimizePath) {
                        HStack { Image(systemName: "arrow.triangle.swap"); Text("최소 동선 정렬") }
                            .frame(maxWidth: .infinity).padding()
                            .background((startPoint == nil || bucketList.isEmpty) ? Color.gray : Color.blue)
                            .foregroundColor(.white).cornerRadius(12)
                    }
                    .disabled(startPoint == nil || bucketList.isEmpty)
                    
                    Button(action: { showMap = true }) {
                        Image(systemName: "map.fill").font(.title2).padding()
                            .background((startPoint == nil) ? Color.gray : Color.green)
                            .foregroundColor(.white).cornerRadius(12)
                    }
                    .disabled(startPoint == nil)
                }
                .padding()
            }
            .navigationTitle("AI 여행 코스 짜기 🗺️")
            .sheet(isPresented: $showFavoritesSheet) {
                VStack {
                    Text("나의 찜 목록 ❤️").font(.headline).padding()
                    List {
                        ForEach(favoriteStore.favorites) { place in
                            Button(action: { addFromFavorite(place) }) {
                                HStack {
                                    let isAdded = bucketList.contains(where: { $0.placeID == place.id })
                                    Image(systemName: "heart.fill").foregroundColor(.red)
                                    Text(place.name).foregroundColor(.primary)
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
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showMap) {
                if let start = startPoint {
                    RouteResultMapView(startPoint: start, waypoints: bucketList)
                }
            }
        }
    }
    
    // 로직
    func searchStartPoint() {
        guard !searchQuery.isEmpty else { return }
        let query = "\(targetRegion) \(searchQuery)"
        placesManager.searchPlaces(query: query) { spot in
            guard let spot = spot else { return }
            withAnimation { self.startPoint = spot; self.isOptimized = false }
            self.searchQuery = ""
        }
    }
    
    func addFromFavorite(_ fav: FavoritePlace) {
        let spot = TravelSpot(
            placeID: fav.id, name: fav.name,
            coordinate: CLLocationCoordinate2D(latitude: fav.latitude, longitude: fav.longitude),
            address: fav.address
        )
        if !bucketList.contains(where: { $0.placeID == spot.placeID }) {
            withAnimation { bucketList.append(spot); isOptimized = false }
        }
    }
    
    func deleteSpot(at index: Int) {
        withAnimation {
            bucketList.remove(at: index)
            isOptimized = false
        }
    }
    
    func optimizePath() {
        guard let start = startPoint else { return }
        let sortedList = RouteOptimizer.optimizeRoute(start: start, destinations: bucketList)
        withAnimation(.spring()) { self.bucketList = sortedList; self.isOptimized = true }
    }
}

// MARK: - 6. 상세 결과 지도 뷰 (딥링크 포함)
struct RouteResultMapView: View {
    let startPoint: TravelSpot
    let waypoints: [TravelSpot]
    @Environment(\.dismiss) var dismiss
    
    @State private var coloredSegments: [ColoredRouteSegment]?
    @StateObject private var directionsManager = DirectionsManager()
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var selectedMode: TransportMode = .transit
    @State private var estimatedTime: String = "-"
    @State private var totalDistance: String = "-"
    
    @State private var routeSteps: [RouteStep] = []
    @State private var showDetails = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TripGoogleMapView(start: startPoint, waypoints: waypoints, coloredSegments: coloredSegments, mode: selectedMode)
                .edgesIgnoringSafeArea(.all)
                .padding(.bottom, showDetails ? 300 : 0)
                .animation(.spring(), value: showDetails)
            
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .padding(10).background(Color.white).clipShape(Circle()).shadow(radius: 3)
                    }
                    Spacer()
                    Picker("이동 수단", selection: $selectedMode) {
                        ForEach(TransportMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 220)
                    .background(Color.white.opacity(0.9)).cornerRadius(8)
                    .onChange(of: selectedMode) { newValue in
                        fetchRoute(mode: newValue)
                    }
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, 50).padding(.horizontal)
                Spacer()
            }
            
            if !isLoading && errorMessage == nil {
                VStack(spacing: 0) {
                    Capsule().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10).padding(.bottom, 5)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("총 소요 시간").font(.caption).foregroundColor(.gray)
                            Text(estimatedTime).font(.title2).bold().foregroundColor(.blue)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("총 거리").font(.caption).foregroundColor(.gray)
                            Text(totalDistance).font(.title2).bold()
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { showDetails.toggle() } }
                    
                    if showDetails {
                        Divider()
                        List {
                            ForEach(routeSteps) { step in
                                HStack(spacing: 15) {
                                    ZStack {
                                        Circle().fill(Color(hex: step.lineColor ?? "#E0E0E0")).frame(width: 36, height: 36)
                                        if step.transportType == "TRANSIT" {
                                            if let name = step.lineName, name.count <= 2 {
                                                Text(name).font(.caption).bold().foregroundColor(.white)
                                            } else {
                                                Image(systemName: "bus.fill").font(.caption).foregroundColor(.white)
                                            }
                                        } else {
                                            Image(systemName: "figure.walk").font(.caption).foregroundColor(.gray)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.instruction).font(.subheadline).bold()
                                        Text(step.detail).font(.caption).foregroundColor(.gray).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(step.duration).font(.caption).bold()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listStyle(.plain).frame(height: 300)
                    }
                }
                .background(Color.white).cornerRadius(20, corners: [.topLeft, .topRight]).shadow(radius: 10)
            }
            
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("\(selectedMode.title) 경로 계산 중...")
                        .padding().background(Color.white).cornerRadius(10).shadow(radius: 5).padding(.bottom, 50)
                }
            } else if let error = errorMessage {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.title)
                        Text("앱 내에서 경로를 그릴 수 없습니다").font(.headline)
                        Text(error).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
                        
                        // [딥링크 버튼]
                        Button(action: openGoogleMaps) {
                            HStack {
                                Text("구글 지도 앱에서 보기").fontWeight(.bold)
                                Image(systemName: "arrow.up.right.circle.fill")
                            }
                            .foregroundColor(.white).padding()
                            .frame(maxWidth: .infinity).background(Color.blue).cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    .padding().background(Color.white).cornerRadius(10).shadow(radius: 5)
                    .padding(.bottom, 50).padding(.horizontal)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear { fetchRoute(mode: selectedMode) }
    }
    
    func fetchRoute(mode: TransportMode) {
        isLoading = true; errorMessage = nil; coloredSegments = nil; routeSteps = []
        directionsManager.fetchRoute(from: startPoint, waypoints: waypoints, mode: mode) { segments, time, dist, steps in
            self.isLoading = false
            if let segments = segments {
                self.coloredSegments = segments
                self.estimatedTime = time ?? "-"
                self.totalDistance = dist ?? "-"
                self.routeSteps = steps ?? []
            } else {
                if mode != .transit && isKoreaRegion() {
                    self.errorMessage = "한국 내 도보/차량 데이터는 구글 정책상 제한됩니다."
                } else if mode == .transit && isJapanRegion() {
                    self.errorMessage = "일본 대중교통 데이터는 구글 정책상 API 반출이 제한됩니다."
                } else {
                    self.errorMessage = "경로 데이터를 불러오지 못했습니다."
                }
            }
        }
    }
    
    func isKoreaRegion() -> Bool {
        return startPoint.address.contains("대한민국") || startPoint.address.contains("Korea")
    }
    
    func isJapanRegion() -> Bool {
        return startPoint.address.contains("Japan") || startPoint.address.contains("일본")
    }
    
    func openGoogleMaps() {
        let origin = "\(startPoint.coordinate.latitude),\(startPoint.coordinate.longitude)"
        let destination = "\(waypoints.last!.coordinate.latitude),\(waypoints.last!.coordinate.longitude)"
        
        var waypointsString = ""
        if waypoints.count > 1 {
            let middlePoints = waypoints.dropLast()
            let coords = middlePoints.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }
            waypointsString = "&waypoints=" + coords.joined(separator: "|")
        }
        
        let urlString = "https://www.google.com/maps/dir/?api=1&origin=\(origin)&destination=\(destination)\(waypointsString)&travelmode=\(selectedMode.rawValue)"
        
        if let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 7. Google Maps Wrapper
struct TripGoogleMapView: UIViewRepresentable {
    let start: TravelSpot
    let waypoints: [TravelSpot]
    let coloredSegments: [ColoredRouteSegment]?
    let mode: TransportMode
    
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: start.coordinate.latitude, longitude: start.coordinate.longitude, zoom: 14)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.clear()
        
        if let segments = coloredSegments {
            let boundsPath = GMSMutablePath()
            for segment in segments {
                if let path = GMSPath(fromEncodedPath: segment.encodedPath) {
                    let polyline = GMSPolyline(path: path)
                    polyline.strokeWidth = 5
                    polyline.strokeColor = segment.color
                    
                    if segment.isWalking {
                        polyline.strokeWidth = 4
                        let styles = [GMSStrokeStyle.solidColor(segment.color), GMSStrokeStyle.solidColor(.clear)]
                        let lengths: [NSNumber] = [10, 5]
                        polyline.spans = GMSStyleSpans(path, styles, lengths, GMSLengthKind.rhumb)
                    }
                    polyline.map = mapView
                    for i in 0..<path.count() { boundsPath.add(path.coordinate(at: i)) }
                }
            }
            let bounds = GMSCoordinateBounds(path: boundsPath)
            mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 80.0))
        } else {
            let path = GMSMutablePath()
            path.add(start.coordinate)
            for spot in waypoints { path.add(spot.coordinate) }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 2; polyline.strokeColor = .lightGray
            polyline.map = mapView
            
            var bounds = GMSCoordinateBounds()
            bounds = bounds.includingCoordinate(start.coordinate)
            for spot in waypoints { bounds = bounds.includingCoordinate(spot.coordinate) }
            mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 60.0))
        }
        
        let startMarker = GMSMarker(position: start.coordinate)
        startMarker.title = "출발"
        startMarker.icon = GMSMarker.markerImage(with: .blue)
        startMarker.map = mapView
        
        for (index, spot) in waypoints.enumerated() {
            let marker = GMSMarker(position: spot.coordinate)
            marker.title = "\(index + 1)"
            marker.icon = GMSMarker.markerImage(with: .red)
            marker.map = mapView
        }
    }
}

extension UIColor {
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hexString: hex))
    }
}

struct TripPlannerView_Previews: PreviewProvider {
    static var previews: some View {
        TripPlannerView().environmentObject(FavoriteStore())
    }
}
