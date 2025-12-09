//
//  TripSeoilApp.swift
//  TripSeoil
//
//  Created by 승준 on 9/16/25.
//
import SwiftUI
import AuthenticationServices
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser
import GoogleMaps
import GooglePlaces
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure() // 여기서 Firebase 시동을 겁니다!
    return true
  }
}

@main
struct TravelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        // 카카오 SDK 초기화
        KakaoSDK.initSDK(appKey: "94b80d568ff2f6e06275e2f22a6ea8ee")

        // Google Maps SDK 초기화 (앱 키를 사용하여)
        GMSServices.provideAPIKey("AIzaSyAyWUuq6RwQ-qAo4KOgVE8Vk4-cBspN_bY")
        GMSPlacesClient.provideAPIKey("AIzaSyAyWUuq6RwQ-qAo4KOgVE8Vk4-cBspN_bY")
        // ... Kakao SDK 초기화 등
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 카카오 로그인 시 URL을 처리하기 위한 코드
                .onOpenURL { url in
                    if (AuthApi.isKakaoTalkLoginUrl(url)) {
                        _ = AuthController.handleOpenUrl(url: url)
                    }
                }
        }
    }
}

