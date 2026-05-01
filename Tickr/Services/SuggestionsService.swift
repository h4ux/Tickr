import Foundation

struct SuggestedGroup: Codable, Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let symbols: [String]
}

struct SuggestionsPayload: Codable {
    let version: Int?
    let suggestions: [SuggestedGroup]
}

class SuggestionsService: ObservableObject {
    static let shared = SuggestionsService()

    @Published var groups: [SuggestedGroup] = []

    private static let remoteEndpoints = [
        "https://service.h4ux.com/suggestions",
        "https://billowing-term-c225.alon-f46.workers.dev/suggestions",
    ]
    private static let cacheKey = "cachedSuggestions"

    private init() {
        loadLocal()
        fetchRemote()
    }

    /// Load from local bundled JSON (compiled into the binary as a fallback)
    private func loadLocal() {
        let localJSON = """
        {"version":1,"suggestions":[
        {"name":"Magnificent 7","icon":"cpu","symbols":["AAPL","MSFT","GOOGL","AMZN","NVDA","META","TSLA"]},
        {"name":"AI & Semiconductors","icon":"bolt","symbols":["NVDA","AMD","AVGO","TSM","INTC","QCOM","ARM"]},
        {"name":"FAANG","icon":"globe","symbols":["META","AAPL","AMZN","NFLX","GOOGL"]},
        {"name":"Crypto Related","icon":"banknote","symbols":["COIN","MSTR","MARA","RIOT","CLSK"]},
        {"name":"EV & Clean Energy","icon":"leaf","symbols":["TSLA","RIVN","LCID","NIO","ENPH","FSLR"]},
        {"name":"Banking","icon":"building.2","symbols":["JPM","BAC","WFC","GS","MS","C"]},
        {"name":"Healthcare","icon":"cross.case","symbols":["JNJ","UNH","PFE","ABBV","MRK","LLY"]},
        {"name":"Gaming","icon":"gamecontroller","symbols":["ATVI","EA","TTWO","RBLX","U"]},
        {"name":"Travel & Airlines","icon":"airplane","symbols":["DAL","UAL","LUV","AAL","ABNB","BKNG"]},
        {"name":"Retail","icon":"cart","symbols":["WMT","COST","TGT","HD","LOW","AMZN"]},
        {"name":"Space","icon":"moon.stars","symbols":["RKLB","LUNR","ASTS","PL","IRDM","SPCE","BKSY","RDW","LMT","BA","NOC","LHX"]},
        {"name":"VanEck Space Innovators UCITS ETF","icon":"moon.stars","symbols":["PL","RKLB","VSAT","SATS","GSAT","ASTS","FLY","LUNR","MDA.TO","IRDM","9412.T","6285.TW","SESG.PA","012450.KS","MRO.L","DCO","NN","ETL.PA","AVIO.MI","RDW","BKSY","186A.T","GILT","464A.T","9348.T"]}
        ]}
        """

        // Try cached remote data first, fall back to local
        if let cachedData = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(SuggestionsPayload.self, from: cachedData) {
            DispatchQueue.main.async { self.groups = cached.suggestions }
        } else if let data = localJSON.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(SuggestionsPayload.self, from: data) {
            DispatchQueue.main.async { self.groups = payload.suggestions }
        }
    }

    /// Fetch from remote endpoints with fallback chain, update cache and UI
    private func fetchRemote() {
        fetchFromEndpoint(index: 0)
    }

    private func fetchFromEndpoint(index: Int) {
        guard index < Self.remoteEndpoints.count,
              let url = URL(string: Self.remoteEndpoints[index]) else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            let http = response as? HTTPURLResponse

            if let data = data, http?.statusCode == 200,
               let payload = try? JSONDecoder().decode(SuggestionsPayload.self, from: data),
               !payload.suggestions.isEmpty {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
                DispatchQueue.main.async {
                    self.groups = payload.suggestions
                }
            } else {
                self.fetchFromEndpoint(index: index + 1)
            }
        }.resume()
    }
}
