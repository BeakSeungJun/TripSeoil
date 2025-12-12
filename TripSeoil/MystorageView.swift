import SwiftUI

struct MyStorageView: View {
    @StateObject private var favoritesManager = FavoritesManager()
    @StateObject private var geminiManager = GeminiManager()
    @State private var showAIResult = false // 결과창 시트
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // [수정 1] AI 버튼을 최상단에 고정 배치 (조건문 밖으로 뺌)
                VStack {
                    Button(action: {
                        showAIResult = true
                        geminiManager.generateItinerary(from: favoritesManager.savedPlaces)
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("AI로 여행 코스 정리받기")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            // 데이터가 없으면 회색, 있으면 그라데이션
                            favoritesManager.savedPlaces.isEmpty
                            ? LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: favoritesManager.savedPlaces.isEmpty ? 0 : 5)
                    }
                    .disabled(favoritesManager.savedPlaces.isEmpty) // 데이터 없으면 클릭 방지
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                
                // [수정 2] 리스트 영역
                if favoritesManager.savedPlaces.isEmpty {
                    // 데이터 없음 (빈 화면)
                    Spacer()
                    VStack(spacing: 15) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("보관함이 비어있습니다.")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("추천 탭에서 ❤️를 눌러 장소를 채워보세요!\n장소가 있어야 AI가 코스를 짜줍니다.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    // 데이터 있음 (리스트)
                    List {
                        ForEach(favoritesManager.savedPlaces) { place in
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(place.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(place.address)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("나만의 보관함 🗂️")
            .onAppear {
                favoritesManager.fetchPlaces()
            }
            .sheet(isPresented: $showAIResult) {
                AIItineraryResultView(geminiManager: geminiManager)
            }
        }
    }
    
    func deleteItems(at offsets: IndexSet) {
        offsets.forEach { index in
            let place = favoritesManager.savedPlaces[index]
            favoritesManager.removePlace(place)
        }
    }
}

// [하위 뷰] AI 결과 표시 화면
struct AIItineraryResultView: View {
    @ObservedObject var geminiManager: GeminiManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            // 헤더
            HStack {
                Text("AI 여행 플래너")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }
            .padding()
            
            Divider()
            
            // 내용
            if geminiManager.isLoading {
                VStack(spacing: 20) {
                    Spacer()
                    ProgressView().scaleEffect(1.5)
                    Text("최적의 동선을 분석 중입니다...\n잠시만 기다려주세요! ")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else if let error = geminiManager.errorMessage {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.orange)
                    Text("오류 발생").font(.headline)
                    Text(error).font(.caption).padding().multilineTextAlignment(.center)
                    Spacer()
                }
            } else {
                ScrollView {
                    Text(geminiManager.aiResponse)
                        .padding()
                        .font(.body)
                        .lineSpacing(6)
                }
            }
        }
    }
}

struct MyStorageView_Previews: PreviewProvider {
    static var previews: some View {
        MyStorageView()
    }
}
