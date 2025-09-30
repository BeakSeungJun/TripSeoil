import SwiftUI

struct WelcomeView: View {
    let username: String
    @State private var navigateToLoggedInView = false
    @State private var opacity: Double = 0.0
    
    var body: some View {
        ZStack {
            // 배경 이미지 추가
            Image("background_3")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                // 투명도를 조절하는 그라데이션 오버레이를 추가합니다.
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.8), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                )
            
            VStack(spacing: 15) {
                Text("\(username)님, 환영합니다!")
                    .font(.system(size: 35, weight: .bold, design: .rounded)) // 폰트 디자인을 .rounded로 변경합니다.
                    .padding(.bottom, 5)
                    .foregroundStyle(.white) // 글자색을 흰색으로 변경
                
                // 추가된 부분: '화면을 터치' 문구
                Text("화면을 터치")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.top, 100)
                    .opacity(opacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            opacity = 1.0
                        }
                    }
            }
            // VStack이 화면 전체를 차지하도록 설정
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // 터치 영역을 사각형으로 명확하게 확장
        }
        .onTapGesture {
            navigateToLoggedInView = true
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToLoggedInView) {
            LoggedInView(username: username)
        }
    }
}
