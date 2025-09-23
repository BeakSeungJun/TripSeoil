import SwiftUI
import AuthenticationServices
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import Combine

// MARK: - 1. 로그인 UI를 담당하는 View
struct LoginView: View {
    // @StateObject: View가 살아있는 동안 ViewModel 인스턴스를 메모리에 유지합니다.
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        ZStack {
            Image("background2")
                .resizable()
                .ignoresSafeArea()
                .scaledToFill()
            
            VStack(spacing: 20) {
                Spacer()
                
                // --- Apple 로그인 버튼 ---
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    viewModel.handleAppleLogin(result: result)
                }
                .frame(width: 250, height: 50)
                .cornerRadius(10)
                
                // --- Kakao 로그인 버튼 ---
                Button(action: {
                    viewModel.kakaoLogin()
                }) {
                    HStack {
                        Image("kakao_login_small")
                            .resizable()
                            .frame(width: 25, height: 25)
                        Spacer()
                        Text("Login with Kakao")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .frame(width:250, height: 50)
                .background(Color(red: 254/255, green: 229/255, blue: 0/255))
                .cornerRadius(10)
                .shadow(radius: 2)
                
                // --- 비회원 로그인 버튼 ---
                NavigationLink(destination: WelcomeView(username: "비회원")) {
                    Text("비회원 로그인")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 250, height: 50)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40) // 버튼 좌우 여백
            .padding(.bottom, 100)
        }
        .navigationTitle("소셜 로그인")
        .navigationBarTitleDisplayMode(.inline)
        // ViewModel의 isLoggedIn 상태에 따라 다음 화면으로 자동 전환됩니다.
        .navigationDestination(isPresented: $viewModel.isLoggedIn) {
            WelcomeView(username: viewModel.username ?? "사용자")
        }
        // ViewModel의 showAlert 상태에 따라 알림창이 표시됩니다.
        .alert("로그인 실패", isPresented: $viewModel.showAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }
}

// MARK: - 2. 로그인 로직을 관리하는 ViewModel
@MainActor
class LoginViewModel: ObservableObject {
    
    @Published var isLoggedIn = false
    @Published var username: String?
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    // MARK: - Kakao Login
    func kakaoLogin() {
        if UserApi.isKakaoTalkLoginAvailable() {
            UserApi.shared.loginWithKakaoTalk { [weak self] (oauthToken, error) in
                self?.handleLoginResponse(error: error)
            }
        } else {
            UserApi.shared.loginWithKakaoAccount { [weak self] (oauthToken, error) in
                self?.handleLoginResponse(error: error)
            }
        }
    }
    
    // MARK: - Apple Login
    func handleAppleLogin(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            print("Apple 로그인 성공!")
            if let appleIDCredential = authResults.credential as? ASAuthorizationAppleIDCredential {
                let fullName = appleIDCredential.fullName
                let givenName = fullName?.givenName ?? ""
                let familyName = fullName?.familyName ?? ""
                let name = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespacesAndNewlines)
                handleLoginSuccess(username: name.isEmpty ? "사용자" : name)
            }
        case .failure(let error):
            handleLoginFailure(error: error)
        }
    }
    
    // MARK: - Private Helper Functions
    // 로그인 과정의 결과를 처리하는 함수
    private func handleLoginResponse(error: Error?) {
        if let error = error {
            handleLoginFailure(error: error)
        } else {
            print("카카오 로그인 성공!")
            fetchKakaoUserInfo()
        }
    }
    
    private func fetchKakaoUserInfo() {
        //사용자의 정보를 가져오는 함수
        UserApi.shared.me() { [weak self] (user, error) in
            if let error = error {
                self?.handleLoginFailure(error: error)
            } else if let user = user {
                let nickname = user.kakaoAccount?.profile?.nickname
                self?.handleLoginSuccess(username: nickname ?? "사용자")
            }
        }
    }
    
    private func handleLoginSuccess(username: String) {
        //로그인 성공 시 사용자 이름을 저장하고 로그인 값을 false에서 true로 변경
        DispatchQueue.main.async {
            self.username = username
            self.isLoggedIn = true
        }
    }
    
    private func handleLoginFailure(error: Error) {
        // 로그인을 실패했을 때
        DispatchQueue.main.async {
            print("로그인 실패: \(error.localizedDescription)")
            self.alertMessage = "로그인에 실패했습니다. 다시 시도해주세요."
            self.showAlert = true
        }
    }
}

