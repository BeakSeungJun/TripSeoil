import SwiftUI
import AuthenticationServices
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser


// MARK: - 1. 메인 뷰 (ContentView)
// 앱의 첫 화면이 될 메인 뷰입니다.
struct ContentView: View {
    var body: some View {
        // `NavigationStack`을 사용하여 화면 전환을 관리
        NavigationStack {
            // `ZStack`을 사용하여 뷰들을 겹겹이 쌓기
            ZStack {
                Image("background") // "
                        .resizable() // 이미지 크기를 조절할 수 있게 함
                        .scaledToFill() // 비율을 유지하면서 화면을 꽉 채움
                        .ignoresSafeArea() //안전영역을 무시
                VStack {
                    //vstack 을 사용하여 내부 뷰들을 수직으로 배열
                    
                    Text("   Seoil TripApp")
                        .font(.system(size: 70, weight: .bold, design: .serif))
                        .padding(.top, 150)
                        .foregroundStyle(.white)
                    
                    NavigationLink(destination: LoginView()) {
                                // 버튼의 모양을 만듭니다.
                                Text("로그인")
                                    .font(.system(size: 20, weight: .bold)) // 글자 크기
                                    .padding() // 버튼 내부 여백
                                    .frame(width: 200) // 버튼 너비
                                    .background(Color.white) // 버튼 배경색
                                    .foregroundColor(.blue) // 버튼 글자색
                                    .cornerRadius(10) // 둥근 모서리
                                    .shadow(radius: 4) // 그림자 효과
                                        }
                        
                                        .padding(.top, 150) // 텍스트와 버튼 사이 여백
                    Spacer()
                }
            }
        }
    }
}

// MARK: - 2. 로그인 뷰 구현
struct LoginView: View {
    func kakaoLogin() {
            if (UserApi.isKakaoTalkLoginAvailable()) {
                UserApi.shared.loginWithKakaoTalk { (oauthToken, error) in
                    if let error = error {
                        print("카카오톡 로그인 실패: \(error.localizedDescription)")
                    } else {
                        print("카카오톡 로그인 성공!")
                        // 로그인 성공 후 사용자 정보 가져오기
                        UserApi.shared.me() { (user, error) in
                            if let error = error {
                                print("사용자 정보 가져오기 실패: \(error.localizedDescription)")
                            } else {
                                if let user = user {
                                    print("사용자 닉네임: \(user.kakaoAccount?.profile?.nickname ?? "없음")")
                                }
                            }
                        }
                    }
                }
            } else {
                // 카카오톡이 설치되어 있지 않을 경우 웹으로 로그인
                UserApi.shared.loginWithKakaoAccount { (oauthToken, error) in
                    if let error = error {
                        print("카카오 계정 로그인 실패: \(error.localizedDescription)")
                    } else {
                        print("카카오 계정 로그인 성공!")
                        // 로그인 성공 후 사용자 정보 가져오기
                        UserApi.shared.me() { (user, error) in
                            if let error = error {
                                print("사용자 정보 가져오기 실패: \(error.localizedDescription)")
                            } else {
                                if let user = user {
                                    print("사용자 닉네임: \(user.kakaoAccount?.profile?.nickname ?? "없음")")
                                }
                            }
                        }
                    }
                }
            }
        }
   //MARK: 로그인 버튼 구현
    var body: some View {
        ZStack {
            
        
                Image("background2") // "
                    .resizable() // 이미지 크기를 조절할 수 있게
                    .ignoresSafeArea() //안전영역을 무시
                    .scaledToFill() // 비율을 유지하면서 화면을 꽉 채움
        VStack() {
            Spacer()
            // 애플 아이디 로그인 버튼을 추가합니다.
            SignInWithAppleButton(.continue) { request in
                // 인증 요청이 시작될 때 호출
                // 사용자 정보를 요청
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                // 인증을 통과해야 호출
                switch result {
                case .success(_):
                    print("애플 로그인 성공!")
                    // authResults를 통해 사용자 정보를 처리
                    
                case .failure(let error):
                    print("애플 로그인 실패: \(error.localizedDescription)")
                }
            }
            .frame(width: 250, height: 50)
            
        
            // 카카오 로그인 버튼
            Button(action: {
                kakaoLogin()
            }) {
                    HStack {
                        
                        // 카카오 로고
                        Image("kakao_login_small")
                            .resizable()
                            .frame(width: 25, height: 25)
                            
                        Text("Login with Kakao")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                           
                        }
                        .frame(width: 250, height: 50)
                        .background(Color(red: 254/255, green: 229/255, blue: 0/255))
                        .cornerRadius(10)
                        .shadow(radius: 4)
                    }
                    .padding(.bottom, 100)
        .navigationTitle("로그인")
        }
        }
    }
}

#Preview {
    ContentView()
}
