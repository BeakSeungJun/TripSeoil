import SwiftUI
import AuthenticationServices
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import Combine // ViewModel을 위해 필요합니다.

// MARK: - 1. 앱 진입점 및 메인 뷰 (ContentView)
// 앱의 첫 화면이 될 메인 뷰입니다.
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
                    
                    // "로그인" 버튼을 누르면 LoginView로 이동합니다.
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

// MARK: - 2. 로그인 UI를 담당하는 View
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
            }
            .padding(.horizontal, 40) // 버튼 좌우 여백
            .padding(.bottom, 100)
        }
        .navigationTitle("소셜 로그인")
        .navigationBarTitleDisplayMode(.inline)
        // ViewModel의 isLoggedIn 상태에 따라 다음 화면으로 자동 전환됩니다.
        .navigationDestination(isPresented: $viewModel.isLoggedIn) {
            LoggedInView(username: viewModel.username ?? "사용자")
        }
        // ViewModel의 showAlert 상태에 따라 알림창이 표시됩니다.
        .alert("로그인 실패", isPresented: $viewModel.showAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }
}

// MARK: - 3. 로그인 로직을 관리하는 ViewModel
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
    private func handleLoginResponse(error: Error?) {
        if let error = error {
            handleLoginFailure(error: error)
        } else {
            print("카카오 로그인 성공!")
            fetchKakaoUserInfo()
        }
    }
    
    private func fetchKakaoUserInfo() {
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
        // UI 상태 변경을 메인 스레드에서 확실하게 실행하도록 감싸줍니다.
        // @MainActor를 사용했으므로 DispatchQueue.main.async는 선택사항이지만, 명시적으로 사용해도 무방합니다.
        DispatchQueue.main.async {
            self.username = username
            self.isLoggedIn = true
        }
    }
    
    private func handleLoginFailure(error: Error) {
        // 에러 처리도 메인 스레드에서 실행하는 것이 안전합니다.
        DispatchQueue.main.async {
            print("로그인 실패: \(error.localizedDescription)")
            self.alertMessage = "로그인에 실패했습니다. 다시 시도해주세요."
            self.showAlert = true
        }
    }
}

// MARK: - 4. 로그인 성공 후 보여줄 뷰
struct LoggedInView: View {
    let username: String
    
    var body: some View {
        VStack(spacing: 15) {
            Text("\(username)님, 환영합니다!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Seoil Trip을 시작해 보세요.")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .navigationTitle("로그인 성공")
        // 뒤로가기 버튼을 자동으로 숨겨서 로그인 화면으로 돌아가지 않도록 합니다.
        .navigationBarBackButtonHidden(true)
    }
}


// MARK: - 6. SwiftUI 미리보기
#Preview {
    ContentView()
}
