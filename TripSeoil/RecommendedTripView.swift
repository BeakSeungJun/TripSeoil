import SwiftUI
import GoogleMaps
import GooglePlaces
import Combine // SwiftUI -> UIKit 통신을 위해 Combine 추가

/**
 * SwiftUI 뷰에서 GMSMapView로 보낼 수 있는 명령
 */
enum MapCommand {
    case zoomIn
    case zoomOut
}

/**
 * SwiftUI에서 Google Map 뷰를 표시하기 위한 UIViewRepresentable 래퍼입니다.
 */
struct GoogleMapView: UIViewRepresentable {
    
    @Binding var places: [GMSPlace]
    @Binding var selectedPlace: GMSPlace?
    // SwiftUI 뷰로부터 명령을 받기 위한 Subject
    let mapControl: PassthroughSubject<MapCommand, Never>
    
    private let defaultZoom: Float = 15.0

    // 1. UIKit 뷰(GMSMapView) 생성
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(
            withLatitude: 37.5665,
            longitude: 126.9780,
            zoom: 12.0
        )
        let mapView = GMSMapView.map(withFrame: .zero, camera: camera)
        mapView.delegate = context.coordinator
        
        // --- '내 위치' 기능 활성화 ---
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true // '내 위치' 버튼
        
        // --- 추가 UI 설정 ---
        mapView.settings.compassButton = true // '나침반' 버튼
        
        // Coordinator가 mapView 인스턴스에 접근할 수 있도록 설정
        context.coordinator.mapView = mapView
        
        return mapView
    }

    // 2. SwiftUI 뷰의 상태가 변경될 때 UIKit 뷰 업데이트
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        uiView.clear()
        
        for place in places {
            let marker = GMSMarker()
            marker.position = place.coordinate
            marker.title = place.name
            marker.snippet = place.formattedAddress
            marker.userData = place
            marker.map = uiView
        }
        
        let targetPlace = selectedPlace ?? places.first
        if let place = targetPlace {
            let cameraUpdate = GMSCameraUpdate.setTarget(place.coordinate, zoom: defaultZoom)
            uiView.animate(with: cameraUpdate)
        }
    }

    // 3. Coordinator 생성
    func makeCoordinator() -> Coordinator {
        // Coordinator 생성 시 mapControl Subject 전달
        Coordinator(self, mapControl: mapControl)
    }

    /**
     * GMSMapView의 델리게이트 이벤트를 처리하는 Coordinator 클래스입니다.
     */
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        weak var mapView: GMSMapView? // GMSMapView 인스턴스 참조
        var cancellable: AnyCancellable? // Combine 구독을 관리

        init(_ parent: GoogleMapView, mapControl: PassthroughSubject<MapCommand, Never>) {
            self.parent = parent
            super.init()
            
            // mapControl Subject를 구독(sink)하여 명령을 처리합니다.
            self.cancellable = mapControl.sink { [weak self] command in
                guard let self = self, let mapView = self.mapView else { return }
                
                switch command {
                case .zoomIn:
                    mapView.animate(with: GMSCameraUpdate.zoomIn())
                case .zoomOut:
                    mapView.animate(with: GMSCameraUpdate.zoomOut())
                }
            }
        }

        // 마커를 탭했을 때 호출
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let place = marker.userData as? GMSPlace {
                parent.selectedPlace = place
            }
            
            let cameraUpdate = GMSCameraUpdate.setTarget(marker.position, zoom: mapView.camera.zoom)
            mapView.animate(with: cameraUpdate)
            return true
        }
        
        // (추가) 맵의 빈 공간을 탭했을 때
        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            // 선택된 장소를 해제하고 정보창을 숨길 수 있습니다.
             parent.selectedPlace = nil
        }
    }
}

/**
 * 메인 SwiftUI 뷰입니다.
 */
struct RecommendedTripView: View {
    
    private let placesClient = GMSPlacesClient.shared()
    
    // --- 지도 제어용 Subject ---
    private let mapControl = PassthroughSubject<MapCommand, Never>()
    
    // --- 지도 관련 상태 ---
    @State private var places: [GMSPlace] = []
    @State private var selectedPlace: GMSPlace? = nil
    
    // --- API 및 UI 상태 ---
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    
    // --- 검색 관련 상태 ---
    @State private var searchQuery: String = ""
    
    var body: some View {
        // ZStack을 사용하여 맵 위에 UI 요소(검색창, 정보 카드)를 띄웁니다.
        ZStack(alignment: .top) {
            
            // 1. Google Map 뷰 (배경)
            GoogleMapView(
                places: $places,
                selectedPlace: $selectedPlace,
                mapControl: mapControl // mapControl 전달
            )
            .edgesIgnoringSafeArea(.all)

            // 2. 검색 UI (상단)
            VStack(spacing: 0) {
                // 검색창 (onSearch 콜백을 performSearch로 연결)
                SearchBarView(searchQuery: $searchQuery, onSearch: performSearch)
            }
            .padding()
            .padding(.top, 40) // 상단 Safe Area 여백
            
            // 3. 확대/축소 버튼 (우측 하단)
            VStack(spacing: 12) {
                Button(action: {
                    mapControl.send(.zoomIn) // Zoom In 명령
                }) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 3)
                }
                
                Button(action: {
                    mapControl.send(.zoomOut) // Zoom Out 명령
                }) {
                    Image(systemName: "minus")
                        .font(.title2.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 3)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            // '내 위치' 버튼(우측 하단) 및 정보 카드(하단)와의 충돌을 피하기 위해
            .padding(.bottom, (selectedPlace == nil ? 100 : 250)) // 정보 카드 높이에 따라 동적
            .animation(.spring(), value: selectedPlace)

            
            // 4. 정보 카드 및 상태 메시지 (하단)
            VStack {
                Spacer() // 하단 정렬을 위해 Spacer 추가
                
                if isLoading {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                
                // 선택된 장소 정보 표시 (애니메이션과 함께)
                if let place = selectedPlace {
                    PlaceInfoView(place: place)
                        .onTapGesture {
                            // (선택) 정보 카드를 탭하면 닫기
                            selectedPlace = nil
                        }
                }
            }
            .padding()
        }
    }
    
    /**
     * 사용자가 검색 버튼을 눌렀을 때 호출됩니다.
     */
    private func performSearch() {
        // UI 정리 (키보드 내리기)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard !searchQuery.isEmpty else { return }

        // API 호출 준비
        isLoading = true
        errorMessage = nil
        
        // 1. 텍스트 쿼리로 장소 검색 (findAutocompletePredictions API 사용)
        // 대한민국(KR) 내에서 검색하도록 필터 설정
        let filter = GMSAutocompleteFilter()
        // filter.country = "KR" // 이 줄을 주석 처리하거나 삭제하여 전 세계로 검색
        
        placesClient.findAutocompletePredictions(
            fromQuery: searchQuery,
            filter: filter,
            sessionToken: nil // 검색 버튼 클릭은 새 세션 시작
        ) { (predictions, error) in
            
            if let error = error {
                self.isLoading = false
                self.errorMessage = "검색 실패: \(error.localizedDescription)"
                return
            }
            
            guard let firstPrediction = predictions?.first else {
                self.isLoading = false
                self.errorMessage = "검색 결과가 없습니다."
                return
            }
            
            // 2. 가장 유력한 결과(첫 번째)의 상세 정보 가져오기
            let placeID = firstPrediction.placeID
            
            // --- 1. 요청 필드 수정 ---
            // .phoneNumber를 .photos로 변경
            let fields: GMSPlaceField = [
                .name, .coordinate, .formattedAddress, .openingHours, .rating,
                .photos,        // 1번: 사진
                .types          // 6번: 장소 유형
            ]
            
            self.placesClient.fetchPlace(
                fromPlaceID: placeID,
                placeFields: fields, // 수정된 fields 전달
                sessionToken: nil // 새 세션
            ) { (place, error) in
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "장소 상세정보 실패: \(error.localizedDescription)"
                    return
                }
                
                guard let place = place else {
                    self.errorMessage = "장소 정보를 찾을 수 없습니다."
                    return
                }
                
                // 지도 상태 업데이트 -> updateUIView 트리거
                self.places = [place]
                self.selectedPlace = place
            }
        }
    }
}

/**
 * 검색창 UI를 위한 서브 뷰
 */
struct SearchBarView: View {
    @Binding var searchQuery: String
    var onSearch: () -> Void // 검색 버튼용 콜백
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            // TextField에서 Return(Enter) 키를 눌러도 검색(onSearch)이 실행됩니다.
            TextField("어디로 갈까요?", text: $searchQuery, onCommit: onSearch)
            
            if !searchQuery.isEmpty {
                Button(action: {
                    self.searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            
            // 검색 버튼 추가
            Button(action: onSearch) {
                Text("검색")
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.2), radius: 5)
    }
}


/**
 * 선택된 장소의 간략한 정보를 표시하는 서브 뷰
 */
struct PlaceInfoView: View {
    let place: GMSPlace
    
    // 사진 로드를 위한 GMSPlacesClient
    private let placesClient = GMSPlacesClient.shared()
    // 로드된 이미지를 저장할 상태 변수
    @State private var placeImage: UIImage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            // --- 1. 사진 표시 ---
            if let image = placeImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150) // 사진 높이 지정
                    .clipped()
                    .cornerRadius(10)
            } else {
                // 사진 로딩 중 또는 사진이 없을 때 Placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 150)
                    .cornerRadius(10)
                    .overlay(ProgressView()) // 로딩 인디케이터
            }
            // ---
            
            Text(place.name ?? "이름 없음")
                .font(.title3)
                .fontWeight(.bold)
            
            Text(place.formattedAddress ?? "주소 정보 없음")
                .font(.subheadline)
            
            // --- 2. 장소 유형 표시 (전화번호 제거됨) ---
            HStack(spacing: 12) {
                
                // --- 수정: 보다 의미 있는 장소 유형 필터링 ---
                // 너무 일반적인 유형을 제외합니다.
                let genericTypes: Set<String> = ["point_of_interest", "establishment"]
                
                // genericTypes에 포함되지 않은 첫 번째 유형을 찾거나,
                // 마땅한 것이 없으면 그냥 첫 번째 유형을 사용합니다.
                let displayType = place.types?.first(where: { !genericTypes.contains($0) }) ?? place.types?.first
                
                if let type = displayType {
                    
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized) // "food_stall" -> "Food stall"
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                
                // (전화번호 HSttack 제거됨)
                Spacer()
            }
            .padding(.top, 2)
            // ---

            if place.rating > 0 {
                HStack {
                    Text("별점: \(String(format: "%.1f", place.rating)) / 5.0")
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
                .font(.callout)
            }
            
            if let openingHours = place.openingHours, let status = openingHours.weekdayText {
                Text(status.first ?? "영업시간 정보")
                    .font(.caption)
                    .foregroundColor(place.isOpen() == .open ? .green : .red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial) // 반투명 배경
        .cornerRadius(12)
        .shadow(radius: 5)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // 'selectedPlace'의 'placeID'가 변경될 때마다 애니메이션 적용
        .animation(.spring(), value: place.placeID)
        .onAppear {
            // 뷰가 나타날 때 사진 로드
            loadPlacePhoto()
        }
        .onChange(of: place.placeID) { oldID, newID in
            // 장소가 변경되면 (예: 다른 마커 탭) 새 사진 로드
            if oldID != newID {
                placeImage = nil // 이전 이미지 초기화
                loadPlacePhoto()
            }
        }
    }
    
    /**
     * GMSPlace의 첫 번째 사진을 비동기적으로 로드합니다.
     */
    private func loadPlacePhoto() {
        guard let photoMetadata = place.photos?.first else {
            print("이 장소에는 사진이 없습니다.")
            return
        }
        
        // GMSPlacesClient를 사용하여 이미지 데이터를 가져옵니다.
        // (적절한 크기 지정)
        placesClient.loadPlacePhoto(
            photoMetadata,
            constrainedTo: CGSize(width: 400, height: 400),
            scale: 1.0
        ) { (photo, error) in
            if let error = error {
                print("사진 로드 오류: \(error.localizedDescription)")
                return
            }
            // 메인 스레드에서 이미지 업데이트
            DispatchQueue.main.async {
                self.placeImage = photo
            }
        }
    }
}


#Preview {
    RecommendedTripView()
}






