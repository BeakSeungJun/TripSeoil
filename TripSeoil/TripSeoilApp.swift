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

@main
struct TravelApp: App {
    init() {
        // 카카오 SDK 초기화
        KakaoSDK.initSDK(appKey: "94b80d568ff2f6e06275e2f22a6ea8ee")
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
