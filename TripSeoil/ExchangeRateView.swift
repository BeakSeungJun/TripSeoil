import Foundation
import SwiftUI
import Combine

// MARK: - 1. 데이터 모델 (Decodable 및 Identifiable 추가)
// API의 실제 응답 구조를 반영
struct Rate: Decodable, Identifiable {
    var id: String { cur_unit } // 통화 단위를 ID로 사용
    
    // API 응답의 성공/실패 코드가 담기는 필드. 이 필드가 없거나 잘못된 타입이면 디코딩 실패
    let result: Int?        // 성공 여부 (1:성공, 2:실패). 값이 없을 수 있으므로 Optional 처리
    let cur_unit: String    // 통화 코드 (예: USD)
    let cur_nm: String      // 통화 이름 (예: 미국 달러)
    let deal_bas_r: Double  // 매매 기준율 (Double로 안전하게 변환)
    
    // JSON 키와 Swift 프로퍼티 이름을 매핑하는 CodingKeys
    private enum CodingKeys: String, CodingKey {
        case result, cur_unit, cur_nm
        case dealBasRString = "deal_bas_r" // JSON에서 String으로 받아올 임시 키
    }
    
    // Decodable 초기화 구문을 수동으로 구현하여 String -> Double 변환 처리
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 1. result, cur_unit, cur_nm 디코딩 (result는 Optional Int로 처리)
        // result 필드는 오류 응답 시에만 존재할 수 있으므로 try?로 안전하게 처리
        self.result = try? container.decode(Int.self, forKey: .result)
        
        // 데이터 필드가 없는 경우를 대비해 기본값 설정
        self.cur_unit = (try? container.decode(String.self, forKey: .cur_unit)) ?? "ERR"
        self.cur_nm = (try? container.decode(String.self, forKey: .cur_nm)) ?? "통화 없음"
        
        // 2. deal_bas_r (매매기준율) String -> Double 변환
        // JSON 파싱 중 오류를 막기 위해 try?로 옵셔널 처리
        guard let dealBasRString = try? container.decode(String.self, forKey: .dealBasRString) else {
            // 이 필드가 디코딩되지 않으면, 0.0으로 처리하고 오류를 던지지 않습니다.
            self.deal_bas_r = 0.0
            return
        }
        
        // 문자열에서 콤마(,) 제거
        let cleanedString = dealBasRString.replacingOccurrences(of: ",", with: "")
        
        // Double 변환 시도, 실패하면 0.0 반환
        self.deal_bas_r = Double(cleanedString) ?? 0.0
    }
}

// MARK: - 2. 뷰 모델 (로직 관리)
@MainActor
final class ExchangeRateViewModel: ObservableObject {
    
    // 화면에 표시할 환율 목록
    @Published var rates: [Rate] = []
    // 검색창의 텍스트를 저장할 상태 변수
    @Published var searchText: String = ""
    // 데이터 로딩 중 상태
    @Published var isLoading = false
    // 에러 메시지 (Optional String)
    @Published var errorMessage: String?
    
    // [추가] 오늘 날짜를 저장할 변수 (YYYYMMDD)
    @Published var searchDate: String = ""
    
    // [추가] 평상 시 표시할 주요 통화 목록 정의 (통화 코드 사용)
    private let majorCurrencies: [String] = ["USD", "EUR", "GBP", "JPY(100)", "CNH"]
    
    // [확장 함수] 통화 코드에 따른 국기 이모지를 반환합니다.
    private func flag(for currencyCode: String) -> String {
        switch currencyCode {
        case "USD": return "🇺🇸" // 미국
        case "EUR": return "🇪🇺" // 유럽 연합
        case "GBP": return "🇬🇧" // 영국
        case "JPY(100)": return "🇯🇵" // 일본 (100)
        case "CNH": return "🇨🇳" // 중국
        case "AUD": return "🇦🇺" // 호주
        case "CAD": return "🇨🇦" // 캐나다
        case "CHF": return "🇨🇭" // 스위스
        case "HKD": return "🇭🇰" // 홍콩
        case "NZD": return "🇳🇿" // 뉴질랜드
        case "SEK": return "🇸🇪" // 스웨덴
        case "SGD": return "🇸🇬" // 싱가포르
        case "THB": return "🇹🇭" // 태국
        default: return "🌐" // 기타
        }
    }
    
    // 검색어에 따라 필터링된 환율 목록을 반환하는 계산된 프로퍼티
    var filteredRates: [Rate] {
        if searchText.isEmpty {
            // [수정] 검색창이 비어있으면, 주요 통화만 필터링하여 반환합니다.
            let majorRates = rates.filter { majorCurrencies.contains($0.cur_unit) }
            
            // 사용자가 원하는 순서대로 정렬 (선택 사항)
            return majorRates.sorted { (rate1, rate2) -> Bool in
                guard let index1 = majorCurrencies.firstIndex(of: rate1.cur_unit),
                      let index2 = majorCurrencies.firstIndex(of: rate2.cur_unit) else {
                    return false
                }
                return index1 < index2
            }
        } else {
            // [수정] 검색창에 내용이 있으면, 전체 목록에서 검색하여 반환합니다.
            let lowercasedQuery = searchText.lowercased()
            return rates.filter { rate in
                // 통화 이름 또는 통화 코드가 검색어를 포함하는지 확인
                return rate.cur_nm.lowercased().contains(lowercasedQuery) ||
                       rate.cur_unit.lowercased().contains(lowercasedQuery) ||
                       // [확장] 국기 코드가 검색어를 포함하는지 확인
                       flag(for: rate.cur_unit).lowercased().contains(lowercasedQuery)
            }
            .sorted { $0.cur_unit < $1.cur_unit } // 검색 결과는 통화 코드 순으로 정렬
        }
    }
    
    // 제공해주신 API 키를 사용합니다.
    private let apiKey = "tRPAh2sV19EzUqycPZ1n8FVPYCju4uIi"
    // 한국수출입은행 API URL 구조
    private var apiURL: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let today = dateFormatter.string(from: Date())
        
        // [수정] searchDate 변수에 오늘 날짜를 저장합니다.
        searchDate = today
        
        // API 요청 URL 구성 (인증키, 오늘 날짜, JSON 타입, 전체 환율 목록)
        return "https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON?authkey=\(apiKey)&searchdate=\(today)&data=AP01"
    }

    init() {
        // 뷰의 onAppear에서 호출하도록 유지
    }
    
    // 환율 데이터를 비동기적으로 가져오는 함수
    func fetchRates() {
        guard !isLoading else { return }
        guard let url = URL(string: apiURL) else {
            errorMessage = "잘못된 API 주소입니다."
            return
        }
        
        isLoading = true
        errorMessage = nil
        rates = []

        // 비동기 작업을 위한 Task
        Task {
            do {
                // 1. URLSession을 사용하여 API 호출 및 데이터 수신
                let (data, response) = try await URLSession.shared.data(from: url)
                
                // HTTP 응답 상태 코드 확인 (200~299 사이가 성공)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                
                // 2. JSONDecoder를 사용하여 데이터 디코딩
                let newRates = try JSONDecoder().decode([Rate].self, from: data)
                
                // 3. API 응답 성공 여부 확인
                // result 필드가 2이고 다른 데이터가 없는 경우 오류로 간주
                if let firstRate = newRates.first,
                   firstRate.result == 2 && newRates.count == 1 {
                    
                    self.errorMessage = "API 인증 또는 조회에 실패했습니다. (주말이거나 인증키, 날짜, 주소 확인 필요)"
                    self.rates = []
                } else {
                    // result 필드가 nil이 아닌 데이터가 포함된 경우 성공으로 처리
                    // result: 1은 성공, result: nil은 환율 데이터 자체를 의미
                    let validRates = newRates.filter { $0.result == nil || $0.result == 1 }
                    
                    // 4. 메인 스레드에서 UI 업데이트
                    self.rates = validRates.sorted { $0.cur_unit < $1.cur_unit }
                }
                
            } catch let decodingError as DecodingError {
                // JSON 파싱 오류 처리
                print("Decoding Error: \(decodingError)") // 디버깅을 위해 콘솔에 출력
                self.errorMessage = "데이터 형식이 잘못되었습니다: \(decodingError.localizedDescription)"
            } catch let urlError as URLError {
                // 네트워크 오류 처리
                self.errorMessage = "네트워크 연결 오류: \(urlError.localizedDescription)"
            } catch {
                // 기타 오류 처리
                self.errorMessage = "환율 정보를 불러오는데 실패했습니다."
            }
            
            // 로딩 완료 상태로 변경
            self.isLoading = false
        }
    }
}

// MARK: - 3. 환율 뷰
// 환율 정보를 화면에 표시하는 뷰입니다.
struct ExchangeRateView: View {
    // 뷰 모델을 연결하여 데이터와 상태를 관찰합니다.
    @StateObject private var viewModel = ExchangeRateViewModel()
    
    // [추가] 사용자가 탭한 환율 정보를 저장하고 계산기 모달을 띄우기 위한 상태 변수
    @State private var selectedRate: Rate?
    
    // [추가] Haptic Feedback 인스턴스
    let feedback = UIImpactFeedbackGenerator(style: .light)
    
    // [확장] 날짜 포맷터 함수
    private func formatDate(dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyyMMdd"
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy년 MM월 dd일"
        
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return "날짜 정보 없음"
    }

    // [확장 함수] 통화 코드에 따른 국기 이모지를 반환합니다.
    private func flag(for currencyCode: String) -> String {
        // JPY(100) 처럼 (100)이 포함된 경우를 대비하여 통화 코드만 추출합니다.
        let cleanedCode = currencyCode.replacingOccurrences(of: "(100)", with: "")
        switch cleanedCode {
        case "USD": return "🇺🇸" // 미국
        case "EUR": return "🇪🇺" // 유럽 연합
        case "GBP": return "🇬🇧" // 영국
        case "JPY": return "🇯🇵" // 일본
        case "CNH": return "🇨🇳" // 중국
        case "AUD": return "🇦🇺" // 호주
        case "CAD": return "🇨🇦" // 캐나다
        case "CHF": return "🇨🇭" // 스위스
        case "HKD": return "🇭🇰" // 홍콩
        case "NZD": return "🇳🇿" // 뉴질랜드
        case "SEK": return "🇸🇪" // 스웨덴
        case "SGD": return "🇸🇬" // 싱가포르
        case "THB": return "🇹🇭" // 태국
        default: return "🌐" // 기타
        }
    }
    
    var body: some View {
        NavigationView { // navigationTitle을 표시하기 위해 NavigationView 추가
            ZStack {
                if viewModel.isLoading {
                    // 1. 로딩 중일 때 로딩 뷰 표시
                    ProgressView("환율 정보를 불러오는 중...")
                        .padding()
                } else if let error = viewModel.errorMessage {
                    // 2. 에러 발생 시 에러 메시지와 재시도 버튼 표시
                    VStack {
                        Text("오류 발생: \(error)")
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 10)
                        Button("다시 시도") {
                            viewModel.fetchRates()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    // 3. 데이터 로드가 성공했을 때 목록 표시
                    List {
                        // [확장] 조회 날짜 정보 표시
                        Text("조회 기준일: \(formatDate(dateString: viewModel.searchDate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        // 필터링된 환율 데이터가 있을 때만 Section 표시
                        if !viewModel.filteredRates.isEmpty {
                            Section(header: Text("기준: 대한민국 원 (KRW)")) {
                                // 필터링된 목록을 표시합니다.
                                ForEach(viewModel.filteredRates) { rate in
                                    // [개선] 카드 스타일 목록 항목
                                    HStack {
                                        // [확장] 국기 이모지 표시
                                        Text(flag(for: rate.cur_unit))
                                            .font(.title)
                                            .padding(.trailing, 8)
                                        
                                        // 통화 이름(name)과 코드(code) 표시
                                        VStack(alignment: .leading) {
                                            HStack(spacing: 4) {
                                                Text(rate.cur_nm) // 예: 미국 달러
                                                    .font(.headline) // 폰트 크기 조정
                                                    .fontWeight(.bold)
                                                // [확장] JPY(100)의 경우 추가 설명 표시
                                                if rate.cur_unit.contains("100") {
                                                    Text("(100원 기준)")
                                                        .font(.caption)
                                                        .foregroundColor(.orange)
                                                }
                                            }
                                            Text(rate.cur_unit) // 예: USD
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        
                                        // 환율 정보를 소수점 2자리로 포맷
                                        VStack(alignment: .trailing) {
                                            Text(String(format: "%.2f", rate.deal_bas_r)) // 'KRW' 제거
                                                .foregroundColor(.blue)
                                                .font(.title2) // 폰트 크기 조정
                                            Text("KRW")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    // [추가] 목록 항목 탭 시 계산기 모달 표시
                                    .contentShape(Rectangle()) // 전체 행에 탭 영역 적용
                                    .onTapGesture {
                                        // [개선] 탭 시 햅틱 피드백 발생
                                        feedback.impactOccurred()
                                        self.selectedRate = rate
                                    }
                                }
                                .listRowBackground(Color(.systemGray6)) // 행 배경색 추가
                                .listRowSeparator(.hidden) // 구분선 제거
                            }
                        } else if viewModel.rates.isEmpty && viewModel.errorMessage == nil {
                            // 데이터가 비어있고 에러 메시지가 없을 때 (초기 로드 또는 검색 결과 없음)
                             Text("조회된 환율 정보가 없습니다.")
                                .foregroundColor(.secondary)
                        } else if !viewModel.searchText.isEmpty && viewModel.filteredRates.isEmpty {
                            // 검색 결과가 없을 때
                            Text("'\(viewModel.searchText)'에 대한 검색 결과가 없습니다.")
                                .foregroundColor(.secondary)
                        }
                    }
                    .listStyle(.plain) // 목록 스타일 변경
                    // 당겨서 새로고침 기능 추가
                    .refreshable {
                        viewModel.fetchRates()
                    }
                    // [추가] 환율 계산기 모달 표시
                    .sheet(item: $selectedRate) { rate in
                        CalculatorView(rate: rate)
                    }
                }
            }
            .navigationTitle("오늘의 환율")
            // 검색창 추가
            .searchable(text: $viewModel.searchText, prompt: "나라 이름이나 통화 코드를 검색하세요")
            // 뷰가 나타날 때 데이터를 한 번 로드
            .onAppear {
                if viewModel.rates.isEmpty {
                    viewModel.fetchRates()
                }
            }
        }
    }
}

// MARK: - 4. 환율 계산기 뷰 (새로 추가)
struct CalculatorView: View {
    // 환경 변수: 모달을 닫기 위해 사용
    @Environment(\.dismiss) var dismiss
    
    // 선택된 환율 정보를 받습니다.
    let rate: Rate
    // 사용자가 입력한 한국 원화 금액
    @State private var krwAmount: String = ""
    
    // 계산된 금액 (Double로 변환)
    private var calculatedForeignAmount: Double {
        // 입력된 KRW 금액에서 콤마를 제거하고 Double로 변환
        let cleanKrwString = krwAmount.replacingOccurrences(of: ",", with: "")
        guard let amount = Double(cleanKrwString), rate.deal_bas_r > 0 else {
            return 0.0
        }
        // 환전 공식: 입력 금액 / 매매 기준율
        // 일본 엔(JPY(100))처럼 100단위인 경우를 고려하여 나누기 100을 해줍니다.
        let adjustedRate = rate.cur_unit.contains("100") ? rate.deal_bas_r / 100 : rate.deal_bas_r
        return amount / adjustedRate
    }
    
    // 한국 원화 입력 포매터 (콤마 추가)
    private var krwFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    // 외국 통화 출력 포매터
    private var foreignFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2 // 소수점 2자리까지 표시
        return formatter
    }

    var body: some View {
        NavigationView { // 닫기 버튼을 위해 NavigationView 추가
            VStack(spacing: 30) {
                
                // 계산 기준 정보 표시
                VStack(spacing: 5) {
                    Text("\(rate.cur_nm) (\(rate.cur_unit))")
                        .font(.title2)
                    Text("기준 환율: \(String(format: "%.2f", rate.deal_bas_r)) KRW")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // 1. KRW 입력 필드
                VStack(alignment: .leading, spacing: 5) {
                    Text("한국 원 (KRW) 입력")
                        .font(.headline)
                    
                    // 숫자만 입력받도록 설정
                    TextField("금액을 입력하세요", text: $krwAmount)
                        // 콤마가 자동으로 추가되도록 포맷팅
                        .onChange(of: krwAmount) { oldValue, newValue in // [수정] 최신 onChange 문법 적용
                            // 입력된 값에서 숫자만 추출
                            let digits = newValue.filter(\.isWholeNumber)
                            
                            // 숫자로 변환하여 포맷터로 다시 문자열로 변환
                            if let number = krwFormatter.number(from: digits) {
                                krwAmount = krwFormatter.string(from: number) ?? ""
                            } else {
                                krwAmount = digits // 숫자가 아닌 문자가 들어오면 제거
                            }
                        }
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)

                // 2. 환전 결과 표시
                VStack(alignment: .leading, spacing: 5) {
                    Text("환전 결과 (\(rate.cur_unit.replacingOccurrences(of: "(100)", with: "")))") // JPY(100)에서 (100) 제거
                        .font(.headline)
                    
                    Text(foreignFormatter.string(from: NSNumber(value: calculatedForeignAmount)) ?? "0.00")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("환율 계산기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // [개선] 닫기 버튼 추가
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 5. 미리보기
#Preview {
    ExchangeRateView()
}
