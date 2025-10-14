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
            // 1. 환영 메시지 영역
            Text("\(username)님, 로그인에 성공했습니다.")
                .font(.headline)
                .padding(.top, 50)
                .padding(.bottom, 20)
            
            // 2. 탭 뷰 (본문 콘텐츠)
            TabView(selection: $selectedTab) {
                // MARK: - 날씨 탭
                // WeatherView() 활성화
                WeatherView()
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



// MARK: - 미리보기
#Preview {
    LoggedInView(username: "홍길동")
}
