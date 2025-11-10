//
// WeatherView.swift
//
// 이 파일은 날씨 정보를 표시하는 뷰(View)와 데이터를 관리하는 뷰 모델(ViewModel)을 포함합니다.
// OpenWeatherMap API를 사용하여 도시 검색 및 실시간 날씨 정보를 가져옵니다.
//
import SwiftUI

// MARK: - 1. 날씨 데이터 모델
// OpenWeatherMap API 응답을 디코딩하기 위한 구조체
struct WeatherResponse: Decodable {
    let name: String
    let weather: [WeatherInfo]
    let main: MainInfo
    let sys: SystemInfo
}

struct WeatherInfo: Decodable {
    let id: Int
    let main: String
    let description: String
    let icon: String
}

struct MainInfo: Decodable {
    let temp: Double
    let temp_min: Double
    let temp_max: Double
}

struct SystemInfo: Decodable {
    let country: String
}

// MARK: - 2. 날씨 뷰 모델 (ViewModel)
@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var weatherData: WeatherResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText: String = "Seoul" // 초기 검색 도시 설정
    
    // API 키를 여기에 입력하세요.
    private let apiKey = "c35246e1b2ee9c9c3907fb09d813735e"
    
    // [수정] init()이 (initialCity: String) 파라미터를 받도록 변경
        init(initialCity: String = "Seoul") {
            self.searchText = initialCity // 전달받은 도시로 searchText 설정
            
            // ViewModel이 생성될 때 초기 날씨 정보를 가져옵니다.
            fetchWeather()
        }
    
    // MARK: - 날씨 정보 가져오기
    func fetchWeather() {
        // 이미 로딩 중이면 중복 요청 방지
        guard !isLoading else { return }
        
        let safeCityName = searchText.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "Seoul"
        
        // OpenWeatherMap API URL 구성 (한국어, 섭씨 기준)
        guard let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?q=\(safeCityName)&units=metric&lang=kr&appid=\(apiKey)") else {
            errorMessage = "잘못된 URL 형식입니다."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "서버 응답이 올바르지 않습니다."
                    self.isLoading = false
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    // API가 404 (도시 없음) 또는 401 (키 오류) 등을 반환했을 때의 처리
                    let status = httpResponse.statusCode
                    if status == 404 {
                        self.errorMessage = "도시를 찾을 수 없습니다. 도시 이름을 영어로 정확히 확인하고 다시 시도해 주세요."
                    } else if status == 401 {
                        self.errorMessage = "API 키 인증에 실패했습니다. 키를 확인하거나 활성화를 기다려주세요."
                    } else {
                        self.errorMessage = "날씨 데이터를 불러오는 데 실패했습니다. (HTTP 상태 코드: \(status))"
                    }
                    self.isLoading = false
                    return
                }
                
                let decoder = JSONDecoder()
                let decodedResponse = try decoder.decode(WeatherResponse.self, from: data)
                
                // 메인 스레드에서 데이터 업데이트
                self.weatherData = decodedResponse
                self.isLoading = false
                
            } catch {
                // 에러 타입에 따라 사용자에게 표시할 메시지를 설정합니다.
                self.errorMessage = "날씨 데이터를 로드하는 중 네트워크 또는 디코딩 오류가 발생했습니다."
                self.isLoading = false
            }
        }
    }
    
    // MARK: - 도시 검색 실행
    func searchCity(cityName: String) {
        self.searchText = cityName
        fetchWeather()
    }
}

// MARK: - 3. 날씨 뷰 (View)
struct WeatherView: View {
    // 뷰 모델을 관찰하여 데이터 변경 시 뷰를 업데이트합니다.
    @StateObject var viewModel = WeatherViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                // 로딩 중이거나 오류 메시지가 있을 때 표시할 화면
                if viewModel.isLoading {
                    ProgressView("날씨 정보 불러오는 중...")
                        .scaleEffect(1.5)
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(message: errorMessage, retryAction: viewModel.fetchWeather)
                } else if let data = viewModel.weatherData {
                    // 데이터가 성공적으로 로드되었을 때 표시할 화면
                    ScrollView {
                        VStack(spacing: 20) {
                            // MARK: - 날씨 카드 디자인
                            WeatherCard(data: data)
                                .shadow(radius: 10)
                            
                            // MARK: - 추가 정보 섹션
                            HStack {
                                Text("기준 시각:")
                                Text(Date(), style: .time)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.top)
                    }
                    // 아래로 당겨서 새로고침 (iOS 15+)
                    .refreshable {
                        viewModel.fetchWeather()
                    }
                } else {
                    // 초기 상태 (데이터가 아직 없는 경우)
                    Text("도시를 검색하거나 잠시 기다려주세요.")
                }
            }
            .navigationTitle("오늘의 날씨")
            // 검색창 추가: 검색 버튼(Return)을 눌렀을 때만 API 호출
            .searchable(text: $viewModel.searchText, prompt: "도시 이름 검색 (예: London, Seoul)")
            .onSubmit(of: .search) {
                viewModel.searchCity(cityName: viewModel.searchText)
            }
            // 뷰가 처음 나타날 때 초기 날씨를 가져옵니다.
            .onAppear {
                if viewModel.weatherData == nil {
                    viewModel.fetchWeather()
                }
            }
        }
    }
}

// MARK: - 4. 뷰 컴포넌트

// 날씨 정보 표시용 카드 컴포넌트
struct WeatherCard: View {
    let data: WeatherResponse
    
    // 섭씨 온도를 소수점 없이 표시
    var currentTemperature: String {
        return String(format: "%.0f°C", data.main.temp)
    }
    
    var body: some View {
        VStack(spacing: 15) {
            // 도시 이름
            Text("\(data.name), \(data.sys.country)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // 현재 온도
            Text(currentTemperature)
                .font(.system(size: 80, weight: .thin))
                .foregroundColor(.white)
            
            // 날씨 상태 (예: Clear, Clouds)
            Text(data.weather.first?.description.capitalized ?? "날씨 정보 없음")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            // 최저/최고 온도
            HStack {
                Image(systemName: "thermometer.snowflake")
                Text("최저: \(String(format: "%.0f°C", data.main.temp_min))")
                
                Spacer()
                
                Image(systemName: "thermometer.sun")
                Text("최고: \(String(format: "%.0f°C", data.main.temp_max))")
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(
            // 그라데이션 배경
            LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .padding(.horizontal)
    }
}

// 오류 메시지 표시 및 재시도 버튼 컴포넌트
struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.largeTitle)
            Text("오류 발생")
                .font(.title2)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("다시 시도") {
                retryAction()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}
