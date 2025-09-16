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
        KakaoSDK.initSDK(appKey: "cdd3ba1b6a52121974365f9c2f560e3c")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 카카오 로그인 시 URL을 처리하기 위한 코드
                .onOpenURL { url in
                    if (AuthApi.isKakaoTalkLoginUrl(url)) {
                        AuthController.handleOpenUrl(url: url)
                    }
                }
        }
    }
}
