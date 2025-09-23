import SwiftUI

// MARK: - 메인 뷰
// 앱이 시작될 때 처음 보여지는 화면입니다.
struct ContentView: View {
    var body: some View {
        // NavigationStack을 사용하여 화면 전환을 관리합니다.
        NavigationStack {
            // ZStack을 사용하여 뷰들을 겹겹이 쌓아 배경 이미지를 표시합니다.
            ZStack {
                // 배경 이미지
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                
                // 배경 이미지 위에 반투명한 검은색 그라데이션을 씌워 텍스트를 돋보이게 합니다.
                LinearGradient(
                    colors: [.black.opacity(0.6), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()
                
                // 앱의 제목과 시작 버튼을 담는 컨테이너입니다.
                VStack(spacing: 20) {
                    Text("Seoil TripApp")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("당신의 완벽한 여행을 시작하세요.")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer() // 남은 공간을 밀어 제목과 버튼을 위로 올립니다.
                    
                    // 로그인 화면으로 이동하는 버튼입니다.
                    NavigationLink(destination: LoginView()) {
                        Text("시작하기")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .frame(maxWidth: 200)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(radius: 5)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

// MARK: - 미리보기
// Xcode의 Canvas에서 뷰를 미리 볼 수 있게 해줍니다.
#Preview {
    ContentView()
}
