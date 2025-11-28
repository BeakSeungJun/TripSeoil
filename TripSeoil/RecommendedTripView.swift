import SwiftUI
import GoogleMaps
import GooglePlaces
import Combine
import CoreLocation

// MARK: - 3. 관광지 카테고리
enum TourismCategory: String, CaseIterable, Identifiable {
    case natural = "🏞️ 자연 관광지"
    case historical = "🏛️ 역사/문화 관광지"
    case experience = "🎭 문화 체험"
    case leisure = "🎡 레저/엔터테인먼트"
    
    var id: String { self.rawValue }
    
    var searchKeywords: [String] {
        switch self {
        case .natural:
            return ["park", "natural feature", "zoo", "garden"]
        case .historical:
            return ["museum", "historic landmark", "castle", "palace", "cathedral", "historic site"]
        case .experience:
            return ["art gallery", "temple", "aquarium", "traditional market", "library"]
        case .leisure:
            return ["amusement park", "shopping mall", "movie theater", "stadium", "theme park"]
        }
    }
    
    var shortName: String {
        switch self {
        case .natural: return "자연"
        case .historical: return "역사/문화"
        case .experience: return "문화 체험"
        case .leisure: return "레저"
        }
    }
}

// MARK: - 4. 메인 지도 뷰 (모든 기능 통합)
struct RecommendedTripView: View {
    
    // --- 뷰 모델 및 저장소 ---
    @StateObject private var weatherViewModel = WeatherViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var favoriteStore: FavoriteStore // 즐겨찾기 저장소
    
    // --- 상태 (State) ---
    @State private var selectedPlace: GMSPlace?
    @State private var searchErrorMessage: String?
    
    @State private var selectedCategory: TourismCategory = .historical
    @State private var cityNameQuery: String = "Seoul"
    
    // [신규] 현재 검색된 도시의 중심 좌표 (기본값: 서울)
    // 이 좌표를 기준으로 주변 장소를 검색하여 '위치 튐' 현상을 방지합니다.
    @State private var currentCityCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    
    @State private var isFetchingLocation = false
    
    // --- 상수 (Constants) ---
    private let placesClient = GMSPlacesClient.shared()
    
    private let mapCommandPublisher = PassthroughSubject<MapCommand, Never>()
    
    // MARK: - 추천 로직
    private func recommendPlaceByCategory() {
        let currentCity = weatherViewModel.searchText
        let keywords = selectedCategory.searchKeywords
        
        guard let randomQuery = keywords.randomElement() else {
            searchErrorMessage = "추천 검색어를 생성하지 못했습니다."
            return
        }

        // 검색어 조합 (예: "museum in Seoul")
        let finalQuery = "\(randomQuery) in \(currentCity)"
        print("카테고리: \(selectedCategory.shortName) -> 추천 검색: \(finalQuery)")
        
        performSearch(query: finalQuery)
    }

    // MARK: - Google Places API 검색 (위치 제한 적용)
    private func performSearch(query: String) {
        self.selectedPlace = nil
        mapCommandPublisher.send(.clearMarkers)
        searchErrorMessage = nil

        guard !query.isEmpty else {
            searchErrorMessage = "검색어를 입력하세요."
            return
        }
        
        // [수정] 검색 필터에 '위치 제한(Restriction)' 적용
        let filter = GMSAutocompleteFilter()
        
        // 현재 설정된 도시 좌표(currentCityCoordinate)를 기준으로
        // 사방 약 0.5도(대략 50km 반경)의 영역을 설정
        let delta = 0.5
        let northEast = CLLocationCoordinate2D(
            latitude: currentCityCoordinate.latitude + delta,
            longitude: currentCityCoordinate.longitude + delta
        )
        let southWest = CLLocationCoordinate2D(
            latitude: currentCityCoordinate.latitude - delta,
            longitude: currentCityCoordinate.longitude - delta
        )
        
        // 이 영역 안의 결과만 반환하도록 강제함 (다른 나라로 튀는 현상 방지)
        filter.locationRestriction = GMSPlaceRectangularLocationOption(northEast, southWest)
        
        placesClient.findAutocompletePredictions(
            fromQuery: query,
            filter: filter, // 필터 적용
            sessionToken: nil
        ) { (predictions, error) in
            
            if let error = error {
                self.searchErrorMessage = "장소 검색 중 오류 발생: \(error.localizedDescription)"
                return
            }
            guard let firstPrediction = predictions?.first else {
                self.searchErrorMessage = "'\(query)'에 대한 검색 결과가 없습니다.\n(현재 도시: \(weatherViewModel.searchText))"
                return
            }
            
            let placeID = firstPrediction.placeID
            // [중요] .placeID 포함 (즐겨찾기 기능용)
            let fields: GMSPlaceField = [
                .name, .coordinate, .formattedAddress, .openingHours, .rating,
                .photos, .types, .placeID
            ]
            
            self.placesClient.fetchPlace(
                fromPlaceID: placeID,
                placeFields: fields,
                sessionToken: nil
            ) { (place, error) in
                if let error = error {
                    self.searchErrorMessage = "장소 세부 정보 오류: \(error.localizedDescription)"
                    return
                }
                guard let place = place else {
                    self.searchErrorMessage = "장소 정보를 가져오지 못했습니다."
                    return
                }
                
                DispatchQueue.main.async {
                    self.selectedPlace = place
                    self.mapCommandPublisher.send(.addMarker(place: place, camera: .move))
                }
            }
        }
    }
    
    /** [수정] 도시 검색 및 좌표 업데이트 */
    private func searchForCity() {
        // 1. 날씨 뷰모델 업데이트
        weatherViewModel.searchCity(cityName: cityNameQuery)
        
        // 2. 입력된 도시 이름으로 실제 좌표 찾기 (Geocoding)
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(cityNameQuery) { placemarks, error in
            if let coordinate = placemarks?.first?.location?.coordinate {
                // 좌표를 찾았으면 업데이트 -> 이후 추천 검색은 이 좌표 주변에서 실행됨
                self.currentCityCoordinate = coordinate
                
                // 변경: 마커 없이 카메라만 이동
                self.mapCommandPublisher.send(.moveCamera(to: coordinate))
                                
                // 도시 자체를 검색어로 한 번 실행
                self.performSearch(query: self.cityNameQuery)
            }
        }
    }

    /** [수정] 현재 위치 기반 추천 */
    private func recommendByCurrentLocation() {
        self.isFetchingLocation = true
        self.searchErrorMessage = nil
        
        locationManager.requestCityName { [self] cityName in
            self.isFetchingLocation = false
            
            guard let cityName = cityName, !cityName.isEmpty else {
                self.searchErrorMessage = "현재 위치의 도시 정보를 가져오지 못했습니다."
                return
            }
            
            self.cityNameQuery = cityName
            weatherViewModel.searchCity(cityName: cityName)
            
            // [신규] 현재 위치 좌표로 기준점 업데이트
            if let location = locationManager.location {
                self.currentCityCoordinate = location.coordinate
            }
            
            self.recommendPlaceByCategory()
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottom) {
            // --- 1. Google Map View ---
            GoogleMapView(
                initialCamera: GMSCameraPosition.camera(
                    withLatitude: 37.5665,
                    longitude: 126.9780,
                    zoom: 12.0
                ),
                commandPublisher: mapCommandPublisher.eraseToAnyPublisher()
            )
            .edgesIgnoringSafeArea(.all)
            
            // --- 2. 상단 UI (도시/테마 선택, 추천 버튼) ---
            VStack(spacing: 0) {
                
                SearchAndCategoryHeaderView(
                    cityNameQuery: $cityNameQuery,
                    selectedCategory: $selectedCategory,
                    onSearch: searchForCity,
                    onGetLocation: recommendByCurrentLocation,
                    isFetchingLocation: isFetchingLocation
                )
                
                // [버튼] 카테고리 기반 추천
                Button(action: recommendPlaceByCategory) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("'\(selectedCategory.shortName)' 테마 장소 추천받기")
                    }
                    .font(.footnote)
                    .fontWeight(.medium)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 5)
                }
                .disabled(weatherViewModel.isLoading)
                
                // 현재 날씨 표시
                if let weather = weatherViewModel.weatherData?.weather.first {
                    Text("현재 \(weatherViewModel.searchText) 날씨: \(weather.description)")
                        .font(.caption)
                        .foregroundColor(.black.opacity(0.8))
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                } else if let weatherError = weatherViewModel.errorMessage {
                    Text(weatherError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // 위치 권한 거부 시 안내 메시지
                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    Text("위치 권한이 거부되었습니다. '내 위치' 기능을 사용하려면 설정에서 권한을 허용해주세요.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                }
                
                // 검색 오류 메시지
                if let searchError = searchErrorMessage {
                    Text(searchError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            
            // --- 3. 하단 UI (장소 정보, 확대/축소) ---
            VStack(spacing: 0) {
                MapControlButtons(commandPublisher: mapCommandPublisher)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                
                if let place = selectedPlace {
                    PlaceInfoView(place: place, placesClient: placesClient)
                        .frame(height: 300)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: selectedPlace)
        }
        .onAppear {
            searchForCity() // 앱 시작 시 기본 도시(서울) 설정
            locationManager.requestPermission()
        }
    }
}

// MARK: - 5. UI 컴포넌트

// --- 도시/테마 선택 헤더 ---
struct SearchAndCategoryHeaderView: View {
    @Binding var cityNameQuery: String
    @Binding var selectedCategory: TourismCategory
    var onSearch: () -> Void
    var onGetLocation: () -> Void
    var isFetchingLocation: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                
                Button(action: onGetLocation) {
                    if isFetchingLocation {
                        ProgressView()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "location.circle.fill")
                            .font(.title2)
                    }
                }
                .padding(.leading, 4)
                .foregroundColor(.blue)
                .disabled(isFetchingLocation)
                
                TextField("도시 이름 (예: London, Paris)", text: $cityNameQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit(onSearch)
                
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            Picker("관광지 종류", selection: $selectedCategory) {
                ForEach(TourismCategory.allCases) { category in
                    Text(category.shortName).tag(category)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.95))
    }
}

// --- 확대/축소 버튼 ---
struct MapControlButtons: View {
    let commandPublisher: PassthroughSubject<MapCommand, Never>
    
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            Button(action: { commandPublisher.send(.zoomIn) }) {
                Image(systemName: "plus")
                    .font(.headline)
                    .padding(10)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.black)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
            Button(action: { commandPublisher.send(.zoomOut) }) {
                Image(systemName: "minus")
                    .font(.headline)
                    .padding(10)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.black)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
        }
    }
}


// --- [UI 개선됨] 장소 정보 뷰 ---
struct PlaceInfoView: View {
    let place: GMSPlace
    let placesClient: GMSPlacesClient
    
    @EnvironmentObject var favoriteStore: FavoriteStore
    
    @State private var placeImage: Image?
    @State private var isLoadingImage = false
    
    private var hasPhotos: Bool { place.photos != nil }
    
    private var ratingString: String? {
        if place.rating > 0 { return String(format: "%.1f", place.rating) }
        return nil
    }
    
    private var openStatus: (isOpen: Bool, text: String)? {
        let status = place.isOpen()
        if status == .unknown { return nil }
        let isOpen = (status == .open)
        return (isOpen, isOpen ? "영업 중" : "영업 종료")
    }
    
    private var categoryTagString: String? {
        let allTypes = place.types ?? []
        let genericTypes: Set<String> = ["point_of_interest", "establishment"]
        let specificTypes = allTypes.filter { !genericTypes.contains($0) }
        
        let typesToFormat: [String]
        if !specificTypes.isEmpty {
            typesToFormat = Array(specificTypes.prefix(2))
        } else {
            typesToFormat = allTypes.first.map { [$0] } ?? []
        }
        if typesToFormat.isEmpty { return nil }
        return typesToFormat
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            .joined(separator: " / ")
    }
    
    private var locationTypeTag: (type: String, isIndoor: Bool)? {
        let allTypesSet = Set(place.types ?? [])
        let indoorTypes: Set<String> = [
            "museum", "aquarium", "cafe", "restaurant", "shopping_mall",
            "movie_theater", "library", "art_gallery", "department_store",
            "bar", "book_store", "spa", "gym", "church", "mosque", "synagogue", "hindu_temple"
        ]
        let outdoorTypes: Set<String> = [
            "park", "zoo", "amusement_park", "stadium", "campground",
            "natural_feature", "tourist_attraction"
        ]

        if !allTypesSet.isDisjoint(with: outdoorTypes) {
            return ("실외", false)
        } else if !allTypesSet.isDisjoint(with: indoorTypes) {
            return ("실내", true)
        }
        return nil
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // 1. 헤더 영역 (고정)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name ?? "이름 없음")
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    
                    if let address = place.formattedAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // ❤️ 하트 버튼
                let placeID = place.placeID ?? UUID().uuidString
                let isFavorite = favoriteStore.isFavorite(placeID)
                
                Button(action: {
                    favoriteStore.toggleFavorite(
                        id: placeID,
                        name: place.name ?? "이름 없음",
                        address: place.formattedAddress ?? "",
                        coordinate: place.coordinate
                    )
                }) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title)
                        .foregroundColor(isFavorite ? .red : .gray.opacity(0.5))
                        .animation(.spring(), value: isFavorite)
                }
            }
            .padding()
            .background(Color.white)
            
            Divider()
            
            // 2. 스크롤 내용 영역
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    
                    if let image = placeImage {
                        image
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 180)
                            .clipped().cornerRadius(10)
                    } else {
                        photoPlaceholderView
                    }
                    
                    if hasPhotos {
                        HStack {
                            Spacer()
                            if placeImage == nil {
                                if !isLoadingImage {
                                    Button(action: loadImage) {
                                        Label("사진 불러오기", systemImage: "photo")
                                            .font(.caption).bold()
                                            .padding(8)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                    }
                                }
                            } else {
                                Button(action: { placeImage = nil }) {
                                    Label("사진 닫기", systemImage: "xmark")
                                        .font(.caption).bold()
                                        .padding(8)
                                        .background(Color.gray.opacity(0.1))
                                        .foregroundColor(.gray)
                                        .cornerRadius(8)
                                }
                            }
                            Spacer()
                        }
                    }
                    
                    HStack(spacing: 12) {
                        if let rating = ratingString {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").foregroundColor(.yellow)
                                Text(rating).fontWeight(.medium)
                            }.font(.subheadline)
                        }
                        
                        if let status = openStatus {
                            Text(status.text)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(status.isOpen ? .green : .red)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        if let categoryString = categoryTagString {
                            Text(categoryString)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1)).foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                        
                        if let tag = locationTypeTag {
                            Text(tag.type)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(tag.isIndoor ? Color.purple.opacity(0.1) : Color.green.opacity(0.1))
                                .foregroundColor(tag.isIndoor ? .purple : .green)
                                .cornerRadius(8)
                        }
                        Spacer()
                    }
                }
                .padding()
            }
        }
        .background(Color.white)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
        .onAppear {
            placeImage = nil
            isLoadingImage = false
        }
    }
    
    @ViewBuilder
    private var photoPlaceholderView: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .frame(height: 150)
                .cornerRadius(10)
            
            if isLoadingImage {
                ProgressView()
            } else if !hasPhotos {
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.3))
                    Text("사진 없음")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                Text("📷 사진을 보려면 버튼을 누르세요")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func loadImage() {
        guard let photoMetadata = place.photos?.first else {
            isLoadingImage = false
            return
        }
        
        isLoadingImage = true
        placesClient.loadPlacePhoto(photoMetadata) { (photo, error) in
            DispatchQueue.main.async {
                if let photo = photo {
                    self.placeImage = Image(uiImage: photo)
                }
                self.isLoadingImage = false
            }
        }
    }
}

// MARK: - 6. Google Map 래퍼
enum MapCommand {
    case clearMarkers
    case addMarker(place: GMSPlace, camera: CameraUpdate)
    case moveCamera(to: CLLocationCoordinate2D)
    case zoomIn
    case zoomOut
}
enum CameraUpdate { case move, none }

struct GoogleMapView: UIViewRepresentable {
    
    let initialCamera: GMSCameraPosition
    let commandPublisher: AnyPublisher<MapCommand, Never>
    
    @State private var mapView = GMSMapView()
    
    func makeUIView(context: Context) -> GMSMapView {
        mapView.camera = initialCamera
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.settings.zoomGestures = true
        
        mapView.delegate = context.coordinator
        context.coordinator.setMapView(mapView)
        return mapView
    }
    
    func updateUIView(_ uiView: GMSMapView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(commandPublisher: commandPublisher)
    }
    
    final class Coordinator: NSObject, GMSMapViewDelegate {
        weak var mapView: GMSMapView?
        private var commandPublisher: AnyPublisher<MapCommand, Never>
        private var cancellables = Set<AnyCancellable>()
        
        init(commandPublisher: AnyPublisher<MapCommand, Never>) {
            self.commandPublisher = commandPublisher
            super.init()
            subscribeToCommandPublisher()
        }
        
        func setMapView(_ mapView: GMSMapView) {
            self.mapView = mapView
        }
        
        func subscribeToCommandPublisher() {
            commandPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] command in
                    guard let self = self, let mapView = self.mapView else { return }
                    switch command {
                    case .clearMarkers:
                        mapView.clear()
                    case .addMarker(let place, let cameraUpdate):
                        mapView.clear()
                        let marker = GMSMarker(position: place.coordinate)
                        marker.title = place.name
                        marker.snippet = place.formattedAddress
                        marker.map = mapView
                        if case .move = cameraUpdate {
                            let camera = GMSCameraPosition.camera(withTarget: place.coordinate, zoom: 15)
                            mapView.animate(to: camera)
                        }
                    case .moveCamera(let coordinate):
                                            let camera = GMSCameraPosition.camera(withTarget: coordinate, zoom: 12)
                                            mapView.animate(to: camera)
                    case .zoomIn:
                        let currentZoom = mapView.camera.zoom
                        mapView.animate(toZoom: currentZoom + 1)
                    case .zoomOut:
                        let currentZoom = mapView.camera.zoom
                        mapView.animate(toZoom: currentZoom - 1)
                    }
                }
                .store(in: &cancellables)
        }
        
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            let camera = GMSCameraPosition.camera(withTarget: marker.position, zoom: mapView.camera.zoom)
            mapView.animate(to: camera)
            return false
        }
    }
}

// MARK: - 7. 유틸리티 확장
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// --- SwiftUI 프리뷰 ---
#if DEBUG
struct RecommendedTripView_Previews: PreviewProvider {
    static var previews: some View {
        RecommendedTripView()
            .environmentObject(FavoriteStore())
    }
}
#endif
