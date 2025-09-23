import SwiftUI

// MARK: - 1. 로그인 성공 후 보여줄 뷰
struct LoggedInView: View {
    let username: String
    
    // 현재 선택된 탭을 추적하는 상태 변수
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - 날씨 탭
            WeatherView()
                .tabItem {
                    Image(systemName: "sun.max.fill")
                    Text("날씨")
                }
                .tag(0)
            
            // MARK: - 환율 탭
            ExchangeRateView()
                .tabItem {
                    Image(systemName: "dollarsign.circle.fill")
                    Text("환율")
                }
                .tag(1)
            
            // MARK: - 추천 여행지 탭
            RecommendedTripView()
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("추천")
                }
                .tag(2)
            
            // MARK: - 가계부 탭
            TravelLedgerView()
                .tabItem {
                    Image(systemName: "book.fill")
                    Text("가계부")
                }
                .tag(3)
            
            // MARK: - 여행 기록 탭
            MyTravelLogView()
                .tabItem {
                    Image(systemName: "pencil.circle.fill")
                    Text("기록")
                }
                .tag(4)
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - 2. 개별 기능 상세 화면
struct WeatherView: View {
    var body: some View {
        Text("날씨 정보를 보여줄 화면입니다.")
            .navigationTitle("오늘의 날씨")
    }
}

struct ExchangeRateView: View {
    var body: some View {
        Text("환율 정보를 보여줄 화면입니다.")
            .navigationTitle("오늘의 환율")
    }
}

struct RecommendedTripView: View {
    var body: some View {
        Text("추천 여행지를 보여줄 화면입니다.")
            .navigationTitle("추천 여행지")
    }
}

struct TravelLedgerView: View {
    var body: some View {
        Text("여행 가계부를 보여줄 화면입니다.")
            .navigationTitle("여행 가계부")
    }
}

struct MyTravelLogView: View {
    var body: some View {
        Text("내 여행 기록을 보여줄 화면입니다.")
            .navigationTitle("내 여행 기록")
    }
}
