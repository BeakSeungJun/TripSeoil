import SwiftUI

struct MyStorageView: View {
    // Firebase 매니저 연결
    @StateObject private var favoritesManager = FavoritesManager()
    
    var body: some View {
        NavigationView {
            VStack {
                if favoritesManager.savedPlaces.isEmpty {
                    // 데이터가 없을 때
                    VStack(spacing: 15) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("보관함이 비어있습니다.")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("추천 탭에서 ❤️를 눌러 장소를 저장해보세요!")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                } else {
                    // 데이터가 있을 때 리스트 표시
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
                // 화면이 뜰 때마다 최신 데이터 불러오기
                favoritesManager.fetchPlaces()
            }
        }
    }
    
    // 스와이프 삭제 기능
    func deleteItems(at offsets: IndexSet) {
        offsets.forEach { index in
            let place = favoritesManager.savedPlaces[index]
            favoritesManager.removePlace(place)
        }
    }
}

struct MyStorageView_Previews: PreviewProvider {
    static var previews: some View {
        MyStorageView()
    }
}
