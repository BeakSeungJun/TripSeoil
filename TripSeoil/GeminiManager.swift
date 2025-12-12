import Foundation
import GoogleGenerativeAI


@MainActor
class GeminiManager: ObservableObject {

    private let apiKey = "AIzaSyA4cz4Si603Qz5xNbcApl4GozJH9B79VnI"
    private var model: GenerativeModel?
    
    @Published var aiResponse: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    init() {
        // 안전 설정 (유해 콘텐츠 차단 해제 등 옵션이 필요하면 여기서 설정)
        self.model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)
    }
    // AI에게 여행지 추천받기
        func recommendAttractions(city: String, category: String, weather: String) async -> [String] {
            guard let model = model else { return [] }
            
            // 프롬프트: "엄격하게 장소 이름만 줘"라고 시킵니다.
            let prompt = """
            Recommend 5 best "\(category)" tourist attractions in "\(city)".
            Current weather is "\(weather)".
            
            [Constraints]
            1. Exclude hotels, guesthouses, hospitals, and simple stores. Only real tourist spots.
            2. Consider the weather (if rain/snow, recommend indoor places).
            3. Output format: Just place names separated by commas. No numbering, no description.
            Example: Place A, Place B, Place C
            """
            
            do {
                let response = try await model.generateContent(prompt)
                guard let text = response.text else { return [] }
                
                // 콤마(,)로 쪼개서 배열로 만듦
                let placeNames = text.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                return placeNames
            } catch {
                print("Gemini 추천 에러: \(error)")
                return []
            }
        }
    // 여행 코스 생성 요청 함수
    func generateItinerary(from places: [TravelSpot]) {
        guard let model = model else { return }
        
        if places.isEmpty {
            self.errorMessage = "저장된 장소가 없습니다."
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        self.aiResponse = ""
        
        // 프롬프트 구성
        let placeListString = places.map { "- \($0.name) (주소: \($0.address))" }.joined(separator: "\n")
        
        let prompt = """
        지금부터 너는 '최고의 여행 동선 설계 전문가'이자 'AI 네비게이터'야.
        내가 여행 가려고 **[저장해 둔 장소 리스트]**를 줄 거야.
        너는 이 장소들의 위치를 파악해서, **이동 시간을 최소화할 수 있는 가장 효율적인 여행 코스**로 재구성해 줘.
            
        반드시 아래의 **[필수 수행 지침]**을 따라서 답변해 줘.
        
        **[저장해 둔 장소 리스트]**
        \(placeListString)
        ---
        **[필수 수행 지침]**

        1.  **지능적 그룹화 (Clustering) & 일정 배분**
            * 내가 준 장소들을 지도상 위치가 가까운 것끼리 묶어라. (예: 동쪽 코스, 시내 중심 코스)
            * 묶인 그룹의 규모에 따라 적절한 여행 일수(예: 1박 2일, 2박 3일)를 제안하고, 일자별로 장소를 배분해라.(적

        2.  **최적 이동 경로 (Routing)**
            * 각 일자별로 **[출발지 → 장소 A → 장소 B → 장소 C → 숙소]** 순서로 가장 효율적인 이동 순서를 정해라.
            * 장소 사이의 이동 방법(도보 10분, 택시 추천, 지하철 n호선 등)을 간략히 명시해라.

        3.  **빈틈 채우기 (Filling the Gaps)**
            * 내가 준 리스트에 '식당'이나 '카페'가 부족하다면, 이동 경로상에 있는 **평점 높은 맛집과 카페**를 자연스럽게 끼워 넣어라. (점심, 저녁, 휴식 시간 고려)

        4.  **꿀팁 및 주의사항**
            * 각 장소의 관람 소요 시간을 예측해서 적어라.
            * 만약 동선이 너무 꼬여서 빼는 게 나은 장소가 있다면 과감하게 "여기는 거리가 머니 다음 기회에"라고 조언해라.
        """
        
    
        Task {
            do {
                let response = try await model.generateContent(prompt)
                
                // [수정 3] @MainActor 덕분에 DispatchQueue.main.async가 필요 없습니다.
                // 바로 값을 변경해도 안전합니다.
                self.isLoading = false
                if let text = response.text {
                    self.aiResponse = text
                } else {
                    self.errorMessage = "AI가 답변을 생성하지 못했습니다."
                }
            } catch {
                self.isLoading = false
                self.errorMessage = "에러 발생: \(error.localizedDescription)"
            }
        }
    }
}
