import SwiftUI
import GoogleMaps

struct MystorageView: View {
    // 저장된 장소 관리 매니저
    @StateObject private var favoritesManager = FavoritesManager()
    
    // AI 코스 생성 매니저
    @StateObject private var geminiManager = GeminiManager()
    
    // AI 결과창 모달 표시 여부
    @State private var showItinerarySheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                if favoritesManager.places.isEmpty {
                    // 저장된 장소가 없을 때 표시
                    VStack(spacing: 20) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("저장된 장소가 없습니다.\n마음에 드는 여행지를 찜해보세요!")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // 저장된 장소 목록 표시
                    VStack {
                        List {
                            ForEach(favoritesManager.places) { place in
                                HStack(spacing: 15) {
                                    // 마커 아이콘
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundColor(.red)
                                    
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(place.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(place.address)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .onDelete(perform: deletePlace) // 스와이프 삭제 기능
                        }
                        .listStyle(InsetGroupedListStyle())
                        
                        // [핵심] AI 코스 짜기 버튼
                        Button(action: {
                            generateCourse()
                        }) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text("이 장소들로 AI 코스 짜기")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .shadow(radius: 5)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("나의 보관함")
            // 화면이 나타날 때마다 최신 목록 불러오기
            .onAppear {
                favoritesManager.fetchPlaces()
            }
            // AI 결과 모달
            .sheet(isPresented: $showItinerarySheet) {
                ItineraryResultView(geminiManager: geminiManager)
            }
        }
    }
    
    // 삭제 로직 연결
    private func deletePlace(at offsets: IndexSet) {
        for index in offsets {
            let place = favoritesManager.places[index]
            favoritesManager.removePlace(place)
        }
    }
    
    // AI 코스 생성 요청
    private func generateCourse() {
        showItinerarySheet = true
        // 저장된 장소 리스트를 AI 매니저에게 전달
        geminiManager.generateItinerary(from: favoritesManager.places)
    }
}

// MARK: - AI 코스 결과 보여주는 모달 뷰
struct ItineraryResultView: View {
    @ObservedObject var geminiManager: GeminiManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if geminiManager.isLoading {
                        // 로딩 중 화면
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Gemini가 최적의 동선을 계산 중입니다...\n잠시만 기다려주세요 🤖")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else if let error = geminiManager.errorMessage {
                        // 에러 화면
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text("오류가 발생했습니다.")
                                .font(.headline)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else {
                        // 결과 텍스트 표시
                        Text(geminiManager.aiResponse)
                            .font(.body)
                            .padding()
                            // 마크다운 스타일 지원을 위해 (iOS 15+)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("AI 추천 코스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

