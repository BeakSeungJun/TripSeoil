//
// RecommendedTripView.swift
//
// 이 파일은 추천 여행 서비스의 모든 모델, 뷰 모델, 뷰 코드를 통합했습니다.
//
import SwiftUI
import MapKit
import Combine
import CoreLocation

// MARK: - 1. 모델 정의 (RecommendationModels.swift 통합)

// 지도 검색 결과 모델
struct SearchResult: Identifiable {
    let id = UUID()
    let placemark: MKPlacemark
}

// 여행 목적 열거형
enum TripPurpose: String, CaseIterable, Identifiable {
    case outdoor = "야외 활동"
    case indoor = "실내 활동"
    case food = "맛집/카페 탐방"
    
    var id: String { self.rawValue }
}

// 날씨 상태 열거형
enum WeatherCondition {
    case sunny, cloudy, rainy // 맑음, 흐림, 비
}

// 추천 장소 모델
struct Recommendation: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let purpose: TripPurpose
    let latitude: Double
    let longitude: Double
    let isRainyDaySpot: Bool // 비 올 때 추천 여부 (true = 실내/맛집)

    var placemark: MKPlacemark {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return MKPlacemark(coordinate: coordinate)
    }
}

// OpenWeatherMap API 응답 모델 (필수 필드만 정의)
struct OpenWeatherResponse: Decodable {
    let weather: [WeatherInfo]
    let name: String? // 도시 이름
}

struct WeatherInfo: Decodable {
    let id: Int
}


// MARK: - 2. 뷰 모델 (TripRecommendationViewModel.swift 통합)

// NOTE: OpenWeatherMap API 키는 유효한 키로 대체해야 합니다.
let openWeatherMapApiKey = "YOUR_OPENWEATHERMAP_API_KEY"

final class TripRecommendationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published Properties (UI State)
    
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780), // 서울 시청
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    @Published var searchText: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var annotations: [SearchResult] = []
    @Published var selectedPurpose: TripPurpose = .outdoor
    @Published var currentWeather: WeatherCondition = .sunny
    @Published var allRecommendations: [Recommendation] = []
    @Published var filteredRecommendations: [Recommendation] = []
    @Published var isLoading: Bool = false
    
    private var localSearch: MKLocalSearch?
    private let locationManager = CLLocationManager()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // 검색어 변경 구독 설정 (Combine)
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self, !newQuery.isEmpty else {
                    self?.searchResults = []
                    self?.updateAnnotations()
                    return
                }
                self.searchForLocations(query: newQuery)
            }
            .store(in: &cancellables)
        
        // 필터링된 목록/검색 결과가 바뀔 때마다 마커를 업데이트합니다.
        Publishers.CombineLatest3($filteredRecommendations, $searchResults, $searchText)
            .sink { [weak self] _, _, _ in
                self?.updateAnnotations()
            }
            .store(in: &cancellables)
        
        // 여행 목적 또는 날씨 상태 변경 시 추천 목록을 필터링합니다.
        Publishers.CombineLatest($selectedPurpose, $currentWeather)
            .sink { [weak self] (purpose, weather) in
                self?.filterRecommendations()
            }
            .store(in: &cancellables)
        
        startLocationUpdates()
        fetchInitialRecommendations()
    }
    
    // MARK: - Location Management
    
    func startLocationUpdates() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // CLLocationManagerDelegate 메서드
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if region.center.latitude == 37.5665 {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        
        locationManager.stopUpdatingLocation()
        fetchWeatherAndRecommendations(for: location.coordinate)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("위치 업데이트 실패: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    // MARK: - Search Logic
    
    private func searchForLocations(query: String) {
        localSearch?.cancel()
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        
        localSearch = MKLocalSearch(request: request)
        
        localSearch?.start { [weak self] response, error in
            guard let self = self else { return }
            // ... (검색 로직은 그대로 유지)
            if let error = error {
                print("지역 검색 실패: \(error.localizedDescription)")
                self.searchResults = []
                return
            }
            
            guard let response = response else {
                self.searchResults = []
                return
            }
            
            self.searchResults = response.mapItems.map { item in
                SearchResult(placemark: item.placemark)
            }
        }
    }
    
    func selectSearchResult(_ result: SearchResult) {
        withAnimation {
            region = MKCoordinateRegion(
                center: result.placemark.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        searchText = result.placemark.name ?? ""
        searchResults = []
    }
    
    // MARK: - API & Recommendation Logic (날씨 API 및 Firestore 로직 통합)
    
    private func fetchInitialRecommendations() {
        // 더미 데이터를 로드하여 allRecommendations에 저장
        self.allRecommendations = [
            Recommendation(name: "남산타워", description: "야외", purpose: .outdoor, latitude: 37.5512, longitude: 126.9880, isRainyDaySpot: false),
            Recommendation(name: "국립중앙박물관", description: "실내", purpose: .indoor, latitude: 37.5230, longitude: 126.9803, isRainyDaySpot: true),
            Recommendation(name: "성수동 카페거리", description: "맛집", purpose: .food, latitude: 37.5445, longitude: 127.0450, isRainyDaySpot: true),
            Recommendation(name: "올림픽 공원", description: "야외", purpose: .outdoor, latitude: 37.5218, longitude: 127.1211, isRainyDaySpot: false),
            Recommendation(name: "코엑스", description: "실내", purpose: .indoor, latitude: 37.5137, longitude: 127.0573, isRainyDaySpot: true)
        ]
        filterRecommendations()
    }
    
    private func fetchWeatherAndRecommendations(for coordinate: CLLocationCoordinate2D) {
        self.isLoading = true
        
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&appid=\(openWeatherMapApiKey)&units=metric&lang=kr"
        
        guard let url = URL(string: urlString) else {
            self.isLoading = false
            print("ERROR: Invalid Weather API URL.")
            return
        }
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                
                let decodedResponse = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
                
                if let weatherCode = decodedResponse.weather.first?.id {
                    DispatchQueue.main.async {
                        self.currentWeather = self.mapWeatherCodeToCondition(code: weatherCode)
                    }
                }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.filterRecommendations()
                    print("날씨 정보 업데이트 성공: \(decodedResponse.name ?? "Unknown City")")
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("날씨 데이터 로드 실패: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func mapWeatherCodeToCondition(code: Int) -> WeatherCondition {
        switch code {
        case 200...599:
            return .rainy
        case 800:
            return .sunny
        default:
            return .cloudy
        }
    }
    
    func filterRecommendations() {
        var results = allRecommendations.filter { $0.purpose == selectedPurpose }
        
        if currentWeather == .rainy {
            results = results.filter { $0.isRainyDaySpot }
        }
        
        self.filteredRecommendations = results
        
        if let firstRecommendation = filteredRecommendations.first {
            withAnimation {
                region = MKCoordinateRegion(
                    center: firstRecommendation.placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            }
        }
    }
    
    // MARK: - Annotation Management & UI Helpers
    
    private func updateAnnotations() {
        if !searchText.isEmpty && !searchResults.isEmpty {
            self.annotations = searchResults
        } else if !filteredRecommendations.isEmpty {
            self.annotations = filteredRecommendations.map { recommendation in
                SearchResult(placemark: recommendation.placemark)
            }
        } else {
            self.annotations = []
        }
    }
    
    func zoom(in isZoomIn: Bool) {
        withAnimation {
            region.span.latitudeDelta /= isZoomIn ? 2 : 0.5
            region.span.longitudeDelta /= isZoomIn ? 2 : 0.5
        }
    }

    var weatherIconName: String {
        switch currentWeather {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rainy: return "cloud.rain.fill"
        }
    }

    var weatherText: String {
        switch currentWeather {
        case .sunny: return "맑음 (야외 활동 추천)"
        case .cloudy: return "흐림 (야외/실내 활동)"
        case .rainy: return "비 (실내 활동 추천)"
        }
    }
}


// MARK: - 3. 뷰 (RecommendedTripView)

struct RecommendedTripView: View {
    @StateObject private var viewModel = TripRecommendationViewModel()
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // 1. 지도 뷰
                Map(coordinateRegion: $viewModel.region,
                    annotationItems: viewModel.annotations) { item in
                    MapMarker(coordinate: item.placemark.coordinate, tint: .blue)
                }
                .edgesIgnoringSafeArea(.all)
                
                // 2. 검색 및 추천 오버레이
                VStack(spacing: 0) {
                    
                    // 2-1. 검색 필드
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("장소, 주소 검색...", text: $viewModel.searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        // 현재 위치 버튼
                        Button(action: viewModel.startLocationUpdates) {
                            Image(systemName: "location.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.top, 50) // 상단 안전 영역
                    .padding(.horizontal)
                    .background(Color.white.opacity(0.8))
                    
                    // 2-2. 추천 UI (날씨 + 목적 선택)
                    VStack(alignment: .leading, spacing: 10) {
                        // 현재 날씨 상태 표시
                        HStack {
                            Image(systemName: viewModel.weatherIconName)
                                .foregroundColor(viewModel.currentWeather == .sunny ? .yellow : .gray)
                            Text("오늘 날씨: \(viewModel.weatherText)")
                        }
                        .font(.subheadline)
                        
                        // 여행 목적 선택 피커
                        Picker("여행 목적", selection: $viewModel.selectedPurpose) {
                            ForEach(TripPurpose.allCases) { purpose in
                                Text(purpose.rawValue).tag(purpose)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        // 로딩 인디케이터
                        if viewModel.isLoading {
                            ProgressView("날씨 정보 가져오는 중...")
                                .padding(.top, 5)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .shadow(radius: 3)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // 2-3. 검색 결과 목록 (오버레이)
                    if !viewModel.searchResults.isEmpty {
                        List(viewModel.searchResults) { result in
                            Button(action: { viewModel.selectSearchResult(result) }) {
                                VStack(alignment: .leading) {
                                    Text(result.placemark.name ?? "이름 없음")
                                        .foregroundColor(.primary)
                                    Text(result.placemark.title ?? "주소 없음")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(maxHeight: 200)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    
                    Spacer() // 나머지 공간을 밀어내 상단에 고정
                }
                
                // 3. 확대/축소 버튼
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        // 확대/축소 버튼 그룹
                        VStack(spacing: 0) {
                            // 확대 버튼
                            Button(action: { viewModel.zoom(in: true) }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .padding(8)
                            }
                            .background(Color.white)
                            
                            Divider().frame(width: 40)
                            
                            // 축소 버튼
                            Button(action: { viewModel.zoom(in: false) }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .padding(8)
                            }
                            .background(Color.white)
                        }
                        .font(.title2)
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                        .shadow(radius: 3)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("날씨 기반 추천 경로")
            .navigationBarHidden(true) // 네비게이션바 숨기고 커스텀 상단 UI 사용
        }
    }
}
