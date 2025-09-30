import SwiftUI
import KakaoSDKUser
import AuthenticationServices
// 다른 뷰 파일들을 사용하기 위해 import 합니다.
// (실제 프로젝트에서는 별도로 파일이 존재해야 합니다.)

// MARK: - 1. 로그인 성공 후 보여줄 뷰
struct LoggedInView: View {
    let username: String
    
    // 현재 선택된 탭을 추적하는 상태 변수
    @State private var selectedTab = 0
    
    var body: some View {
        // ZStack 대신 TabView를 사용하여 화면 상단에 환영 메시지를 띄웁니다.
        // NavigationView를 사용하지 않으므로, 환영 메시지는 탭 내용 위에 고정됩니다.
        VStack(spacing: 0) {
        
            TabView(selection: $selectedTab) {
                // MARK: - 날씨 탭
                // WeatherView()
                Text("날씨 탭 준비 중...")
                    .tabItem {
                        Image(systemName: "sun.max.fill")
                        Text("날씨")
                    }
                    .tag(0)
                
                // MARK: - 환율 탭
                // ExchangeRateView를 연결합니다.
                ExchangeRateView()
                    .tabItem {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("환율")
                    }
                    .tag(1)
                
                // MARK: - 추천 여행지 탭
                // RecommendedTripView()
                Text("추천 탭 준비 중...")
                    .tabItem {
                        Image(systemName: "map.fill")
                        Text("추천")
                    }
                    .tag(2)
                
                // MARK: - 가계부 탭
                // TravelLedgerView()
                Text("가계부 탭 준비 중...")
                    .tabItem {
                        Image(systemName: "book.fill")
                        Text("가계부")
                    }
                    .tag(3)
                
                // MARK: - 여행 기록 탭
                // MyTravelLogView()
                Text("기록 탭 준비 중...")
                    .tabItem {
                        Image(systemName: "pencil.circle.fill")
                        Text("기록")
                    }
                    .tag(4)
            }
            .accentColor(.blue) // 탭 아이템 색상 변경
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - 2. 개별 기능 상세 화면 (Placeholder)
// 이 뷰들은 각자의 .swift 파일로 분리되어 있습니다.
// NOTE: 임시 뷰들을 주석 처리하거나 제거했습니다. 환율 뷰는 별도 파일로 존재한다고 가정합니다.

/*
struct WeatherView: View { @StateObject var viewModel = WeatherViewModel(); var body: Text("날씨 정보를 보여줄 화면입니다.") }
struct RecommendedTripView: View { var body: Text("추천 여행지를 보여줄 화면입니다.") }
struct TravelLedgerView: View { var body: Text("여행 가계부를 보여줄 화면입니다.") }
struct MyTravelLogView: View { var body: Text("내 여행 기록을 보여줄 화면입니다.") }
*/


// MARK: - 미리보기
#Preview {
    LoggedInView(username: "홍길동")
}
