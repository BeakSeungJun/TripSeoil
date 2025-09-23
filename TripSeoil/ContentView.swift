// MARK: - 1. 앱 진입점 및 메인 뷰 (ContentView)
// 앱의 첫 화면이 될 메인 뷰입니다.

import SwiftUI

struct ContentView: View {
    var body: some View {
        // NavigationStack을 사용하여 화면 전환을 관리합니다.
        NavigationStack {
            ZStack {
                // 배경 이미지를 설정합니다.
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("Seoil Trip")
                        .font(.system(size: 70, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .padding(.top, 150)

                    Spacer()

                    // "로그인" 버튼을 누르면    LoginView로 이동합니다.
                    NavigationLink(destination: LoginView()) {
                        Text("로그인")
                            .font(.system(size: 20, weight: .bold))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white)
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                            .shadow(radius: 4)
                            .padding(.horizontal, 40) // 좌우 여백 추가
                    }
                    .padding(.bottom, 100)
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
