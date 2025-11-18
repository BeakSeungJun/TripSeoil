// LocationManager.swift
// (새 파일로 생성)

import SwiftUI
import CoreLocation
import GoogleMaps // GMSGeocoder를 위해 필요

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    let locationManager = CLLocationManager()
    let geocoder = GMSGeocoder()
    
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var location: CLLocation?
    @Published var cityName: String?
    @Published var isFetching: Bool = false
    
    // 비동기 요청을 처리하기 위한 완료 핸들러
    private var completion: ((_ cityName: String?) -> Void)?
    
    override init() {
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }
    
    /// 1. 위치 권한을 요청합니다.
    func requestPermission() {
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    /// 2. 현재 도시 이름을 비동기적으로 요청합니다.
    func requestCityName(completion: @escaping (_ cityName: String?) -> Void) {
        self.isFetching = true
        self.completion = completion
        
        switch authorizationStatus {
        case .notDetermined:
            // 권한이 아직 결정되지 않았으면 요청
            requestPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            // 권한이 있으면 위치 요청 시작
            locationManager.requestLocation()
        case .denied, .restricted:
            // 권한이 거부되었으면 즉시 nil 반환
            finishRequest(with: nil)
        @unknown default:
            finishRequest(with: nil)
        }
    }
    
    /// 3. 요청 완료 처리를 위한 헬퍼
    private func finishRequest(with cityName: String?) {
        DispatchQueue.main.async {
            self.isFetching = false
            self.completion?(cityName)
            self.completion = nil
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    /// 권한 상태가 변경되었을 때 호출
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.authorizationStatus = status
        
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            // 권한을 방금 받았다면, 대기 중이던 요청을 실행
            locationManager.requestLocation()
        } else if status == .denied || status == .restricted {
            // 권한이 거부되었다면, 대기 중이던 요청을 실패 처리
            finishRequest(with: nil)
        }
    }
    
    /// 위치 정보를 성공적으로 가져왔을 때
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            finishRequest(with: nil)
            return
        }
        
        self.location = location
        
        // 4. 좌표 -> 도시 이름 변환 (리버스 지오코딩)
        geocoder.reverseGeocodeCoordinate(location.coordinate) { [weak self] (response, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("GMSGeocoder 오류: \(error.localizedDescription)")
                self.finishRequest(with: nil)
                return
            }
            
            if let address = response?.firstResult() {
                // 'locality'는 "Seoul" 같은 도시 이름, 'administrativeArea'는 "Seoul Metropolitan Government" 같은 행정 구역
                let city = address.locality ?? address.administrativeArea
                self.cityName = city
                self.finishRequest(with: city)
            } else {
                self.finishRequest(with: nil)
            }
        }
    }
    
    /// 위치 정보 가져오기 실패
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("CLLocationManager 오류: \(error.localizedDescription)")
        finishRequest(with: nil)
    }
}
