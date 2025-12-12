import SwiftUI
import GoogleMaps
import GooglePlaces
import Combine
import CoreLocation

// MARK: - 1. 관광지 카테고리
enum TourismCategory: String, CaseIterable, Identifiable {
    case natural = "🏞️ 자연 관광지"
    case historical = "🏛️ 역사/문화 관광지"
    case experience = "🎭 문화 체험"
    case leisure = "🎡 레저/엔터테인먼트"
    
    var id: String { self.rawValue }
    
    var searchKeywords: [String] {
        switch self {
        case .natural:
            return ["park", "national park", "botanical garden", "zoo", "aquarium", "mountain", "lake", "river", "beach"]
        case .historical:
            return ["museum", "history museum", "art museum", "historic site", "palace", "castle", "temple", "cathedral", "monument"]
        case .experience:
            return ["art gallery", "traditional market", "night market", "library", "workshop", "observatory", "planetarium"]
        case .leisure:
            return ["amusement park", "theme park", "shopping mall", "outlet", "movie theater", "stadium", "resort"]
        }
    }
    
    var shortName: String {
        switch self {
        case .natural: return "Nature"
        case .historical: return "History"
        case .experience: return "Culture"
        case .leisure: return "Leisure"
        }
    }
}

// MARK: - 2. 메인 지도 뷰
struct RecommendedTripView: View {
    
    @StateObject private var weatherViewModel = WeatherViewModel()
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var favoriteStore: FavoriteStore
    
    // AI 매니저 연결
    @StateObject private var geminiManager = GeminiManager()
    
    @State private var selectedPlace: GMSPlace?
    @State private var searchErrorMessage: String?
    
    @State private var selectedCategory: TourismCategory = .historical
    @State private var cityNameQuery: String = "Seoul"
    
    @State private var currentCityCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    
    @State private var isFetchingLocation = false
    @State private var isSearching = false
    
    private let placesClient = GMSPlacesClient.shared()
    private let mapCommandPublisher = PassthroughSubject<MapCommand, Never>()
    
    // MARK: - [AI] 추천 로직
    private func recommendPlaceByCategory() {
        let currentCity = weatherViewModel.searchText
        let weatherMain = weatherViewModel.weatherData?.weather.first?.main ?? "Clear"
        
        // UI 리셋
        selectedPlace = nil
        isSearching = true
        searchErrorMessage = nil
        mapCommandPublisher.send(.clearMarkers)
        
        Task {
            print("🤖 AI에게 장소 추천 요청 중: \(currentCity)")
            
            let recommendations = await geminiManager.recommendAttractions(
                city: currentCity,
                category: selectedCategory.shortName,
                weather: weatherMain
            )
            
            if let bestPick = recommendations.randomElement() {
                print("✅ AI 추천 성공: \(bestPick)")
                performSearch(query: "\(bestPick) in \(currentCity)")
            } else {
                print("⚠️ AI 응답 없음 -> 기존 방식(Fallback)")
                fallbackSearch(city: currentCity, weather: weatherMain)
            }
        }
    }
    
    private func fallbackSearch(city: String, weather: String) {
        let isBadWeather = ["Rain", "Snow"].contains(weather)
        let keyword = selectedCategory.searchKeywords.randomElement() ?? "landmark"
        let query = isBadWeather ? "Famous Indoor \(keyword) in \(city)" : "Famous \(keyword) in \(city)"
        performSearch(query: query)
    }

    // MARK: - Google Places API 검색
    private func performSearch(query: String) {
        DispatchQueue.main.async {
            // 좌표 계산
            let centerLat = self.currentCityCoordinate.latitude
            let centerLng = self.currentCityCoordinate.longitude
            let offset: Double = 0.5
            
            let ne = CLLocationCoordinate2D(latitude: centerLat + offset, longitude: centerLng + offset)
            let sw = CLLocationCoordinate2D(latitude: centerLat - offset, longitude: centerLng - offset)
            
            let filter = GMSAutocompleteFilter()
            filter.locationRestriction = GMSPlaceRectangularLocationOption(ne, sw)
            
            self.placesClient.findAutocompletePredictions(fromQuery: query, filter: filter, sessionToken: nil) { (predictions, error) in
                
                if let error = error {
                    self.searchErrorMessage = "검색 오류: \(error.localizedDescription)"
                    self.isSearching = false
                    return
                }
                
                guard let firstResult = predictions?.first else {
                    self.searchErrorMessage = "검색 결과가 없습니다: \(query)"
                    self.isSearching = false
                    return
                }
                
                // [중요] photos, userRatingsTotal 필드 포함
                let fields: GMSPlaceField = [.name, .coordinate, .formattedAddress, .rating, .photos, .types, .placeID, .userRatingsTotal]
                
                self.placesClient.fetchPlace(fromPlaceID: firstResult.placeID, placeFields: fields, sessionToken: nil) { (place, error) in
                    self.isSearching = false
                    
                    if let place = place {
                        self.selectedPlace = place
                        self.mapCommandPublisher.send(.addMarker(place: place, camera: .move))
                    } else {
                        self.searchErrorMessage = "장소 정보를 불러올 수 없습니다."
                    }
                }
            }
        }
    }
    
    private func searchForCity() {
        weatherViewModel.searchCity(cityName: cityNameQuery)
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(cityNameQuery) { placemarks, error in
            if let coordinate = placemarks?.first?.location?.coordinate {
                self.currentCityCoordinate = coordinate
                self.mapCommandPublisher.send(.moveCamera(to: coordinate))
            }
        }
    }

    private func recommendByCurrentLocation() {
        self.isFetchingLocation = true
        self.searchErrorMessage = nil
        
        locationManager.requestCityName { [self] cityName in
            self.isFetchingLocation = false
            guard let cityName = cityName, !cityName.isEmpty else {
                self.searchErrorMessage = "위치 정보를 가져오지 못했습니다."
                return
            }
            self.cityNameQuery = cityName
            weatherViewModel.searchCity(cityName: cityName)
            if let location = locationManager.location { self.currentCityCoordinate = location.coordinate }
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottom) {
            GoogleMapView(
                initialCamera: GMSCameraPosition.camera(withLatitude: 37.5665, longitude: 126.9780, zoom: 12.0),
                commandPublisher: mapCommandPublisher.eraseToAnyPublisher()
            ).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                SearchAndCategoryHeaderView(
                    cityNameQuery: $cityNameQuery,
                    selectedCategory: $selectedCategory,
                    onSearch: searchForCity,
                    onGetLocation: recommendByCurrentLocation,
                    isFetchingLocation: isFetchingLocation
                )
                
                Button(action: recommendPlaceByCategory) {
                    HStack {
                        if isSearching {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text(" AI가 장소를 고르는 중...").font(.footnote).fontWeight(.medium)
                        } else {
                            Image(systemName: "sparkles")
                            if let weather = weatherViewModel.weatherData?.weather.first?.main, ["Rain", "Snow"].contains(weather) {
                                Text("'\(selectedCategory.shortName)' 실내 명소 추천 (AI) ☔️")
                            } else {
                                Text("'\(selectedCategory.shortName)' 명소 추천 (AI)")
                            }
                        }
                    }
                    .font(.footnote).fontWeight(.medium).padding(10).frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .foregroundColor(.white).cornerRadius(10).padding(.horizontal).padding(.bottom, 5)
                }
                .disabled(weatherViewModel.isLoading || isSearching)
                
                if let weather = weatherViewModel.weatherData?.weather.first {
                    Text("현재 \(weatherViewModel.searchText) 날씨: \(weather.description)")
                        .font(.caption).foregroundColor(.black.opacity(0.8)).padding(.horizontal).padding(.bottom, 5)
                }
                
                if let searchError = searchErrorMessage {
                    Text(searchError).font(.caption).foregroundColor(.red).padding(.horizontal)
                }
                Spacer()
            }
            
            VStack(spacing: 0) {
                MapControlButtons(commandPublisher: mapCommandPublisher).padding(.horizontal, 16).padding(.bottom, 8)
                if let place = selectedPlace {
                    PlaceInfoView(place: place, placesClient: placesClient)
                        .frame(height: 450)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: selectedPlace)
        }
        .onAppear {
            searchForCity()
            locationManager.requestPermission()
        }
    }
}

// MARK: - 3. UI 컴포넌트

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
                    if isFetchingLocation { ProgressView().frame(width: 24, height: 24) }
                    else { Image(systemName: "location.circle.fill").font(.title2) }
                }
                .padding(.leading, 4).foregroundColor(.blue).disabled(isFetchingLocation)
                
                TextField("도시 이름 (예: London, Paris)", text: $cityNameQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).onSubmit(onSearch)
                
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass").padding(10).background(Color.blue).foregroundColor(.white).cornerRadius(8)
                }
            }
            Picker("관광지 종류", selection: $selectedCategory) {
                ForEach(TourismCategory.allCases) { category in Text(category.shortName).tag(category) }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(.horizontal).padding(.vertical, 10).background(Color.white.opacity(0.95))
    }
}

struct MapControlButtons: View {
    let commandPublisher: PassthroughSubject<MapCommand, Never>
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            Button(action: { commandPublisher.send(.zoomIn) }) {
                Image(systemName: "plus").font(.headline).padding(10).background(Color.white.opacity(0.9)).foregroundColor(.black).clipShape(Circle()).shadow(radius: 3)
            }
            Button(action: { commandPublisher.send(.zoomOut) }) {
                Image(systemName: "minus").font(.headline).padding(10).background(Color.white.opacity(0.9)).foregroundColor(.black).clipShape(Circle()).shadow(radius: 3)
            }
        }
    }
}

// [수정 완료] PlaceInfoView
struct PlaceInfoView: View {
    let place: GMSPlace
    let placesClient: GMSPlacesClient
    
    @EnvironmentObject var favoriteStore: FavoriteStore
    let firestoreManager = FavoritesManager()
    
    @State private var placeImage: Image?
    @State private var isLoadingImage = false
    
    private var hasPhotos: Bool { place.photos != nil && !place.photos!.isEmpty }
    
    private var ratingString: String? {
        if place.rating > 0 { return String(format: "%.1f", place.rating) }
        return nil
    }
    
    private var categoryTagString: String? {
        let allTypes = place.types ?? []
        let genericTypes: Set<String> = ["point_of_interest", "establishment"]
        let specificTypes = allTypes.filter { !genericTypes.contains($0) }
        let typesToFormat = specificTypes.prefix(2)
        if typesToFormat.isEmpty { return nil }
        return typesToFormat.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: " / ")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (이름, 주소, 즐겨찾기)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name ?? "이름 없음").font(.title2).fontWeight(.bold).lineLimit(1)
                    if let address = place.formattedAddress { Text(address).font(.caption).foregroundColor(.gray).lineLimit(1) }
                }
                Spacer()
                let placeID = place.placeID ?? UUID().uuidString
                let isFavorite = favoriteStore.isFavorite(placeID)
                
                Button(action: {
                    favoriteStore.toggleFavorite(id: placeID, name: place.name ?? "", address: place.formattedAddress ?? "", coordinate: place.coordinate)
                    let spot = TravelSpot(placeID: placeID, name: place.name ?? "", coordinate: place.coordinate, address: place.formattedAddress ?? "")
                    
                    if isFavorite { firestoreManager.removePlace(spot) } else { firestoreManager.addPlace(spot) }
                }) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title)
                        .foregroundColor(isFavorite ? .red : .gray.opacity(0.5))
                        .animation(.spring(), value: isFavorite)
                }
            }
            .padding().background(Color.white)
            
            Divider()
            
            // 메인 내용
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 이미지 자동 로드 및 크기 키움
                    if let image = placeImage {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 250)
                            .clipped().cornerRadius(12)
                    } else {
                        ZStack {
                            Rectangle().fill(Color.gray.opacity(0.1)).frame(height: 250).cornerRadius(12)
                            if isLoadingImage {
                                ProgressView().scaleEffect(1.5)
                            } else if !hasPhotos {
                                Text("사진 없음").font(.caption).foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // 별점 & 리뷰수
                    HStack(spacing: 12) {
                        if let rating = ratingString {
                            HStack(spacing: 4) { Image(systemName: "star.fill").foregroundColor(.yellow); Text(rating).fontWeight(.medium) }.font(.subheadline)
                        }
                        if place.userRatingsTotal > 0 {
                            Text("(\(place.userRatingsTotal)개 리뷰)").font(.caption).foregroundColor(.gray)
                        }
                    }
                    
                    // 카테고리 태그
                    if let categoryString = categoryTagString {
                        Text(categoryString)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .background(Color.white).cornerRadius(20, corners: [.topLeft, .topRight]).shadow(radius: 10)
        // 뷰 나타날 때 이미지 자동 로드
        .onAppear {
            placeImage = nil
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let photoMetadata = place.photos?.first else { return }
        isLoadingImage = true
        // [수정 완료] scale 파라미터 추가하여 오류 해결
        placesClient.loadPlacePhoto(photoMetadata, constrainedTo: CGSize(width: 600, height: 400), scale: 1.0) { (photo, error) in
            DispatchQueue.main.async {
                if let photo = photo { self.placeImage = Image(uiImage: photo) }
                self.isLoadingImage = false
            }
        }
    }
}

// MARK: - 4. Google Map 래퍼
enum MapCommand { case clearMarkers, addMarker(place: GMSPlace, camera: CameraUpdate), moveCamera(to: CLLocationCoordinate2D), zoomIn, zoomOut }
enum CameraUpdate { case move, none }

struct GoogleMapView: UIViewRepresentable {
    let initialCamera: GMSCameraPosition
    let commandPublisher: AnyPublisher<MapCommand, Never>
    @State private var mapView = GMSMapView()
    
    func makeUIView(context: Context) -> GMSMapView {
        mapView.camera = initialCamera; mapView.isMyLocationEnabled = true; mapView.settings.myLocationButton = true; mapView.delegate = context.coordinator; context.coordinator.setMapView(mapView); return mapView
    }
    func updateUIView(_ uiView: GMSMapView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(commandPublisher: commandPublisher) }
    
    final class Coordinator: NSObject, GMSMapViewDelegate {
        weak var mapView: GMSMapView?
        private var commandPublisher: AnyPublisher<MapCommand, Never>
        private var cancellables = Set<AnyCancellable>()
        init(commandPublisher: AnyPublisher<MapCommand, Never>) { self.commandPublisher = commandPublisher; super.init(); subscribeToCommandPublisher() }
        func setMapView(_ mapView: GMSMapView) { self.mapView = mapView }
        func subscribeToCommandPublisher() {
            commandPublisher.receive(on: DispatchQueue.main).sink { [weak self] command in
                guard let self = self, let mapView = self.mapView else { return }
                switch command {
                case .clearMarkers: mapView.clear()
                case .addMarker(let place, let cameraUpdate):
                    mapView.clear(); let marker = GMSMarker(position: place.coordinate); marker.title = place.name; marker.snippet = place.formattedAddress; marker.map = mapView
                    if case .move = cameraUpdate { mapView.animate(to: GMSCameraPosition.camera(withTarget: place.coordinate, zoom: 15)) }
                case .moveCamera(let coordinate): mapView.animate(to: GMSCameraPosition.camera(withTarget: coordinate, zoom: 12))
                case .zoomIn: mapView.animate(toZoom: mapView.camera.zoom + 1)
                case .zoomOut: mapView.animate(toZoom: mapView.camera.zoom - 1)
                }
            }.store(in: &cancellables)
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View { clipShape(RoundedCorner(radius: radius, corners: corners)) }
}
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity; var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path { UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath.uipath }
}
extension CGPath { var uipath: Path { Path(self) } }

#if DEBUG
struct RecommendedTripView_Previews: PreviewProvider {
    static var previews: some View { RecommendedTripView().environmentObject(FavoriteStore()) }
}
#endif
