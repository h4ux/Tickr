import Foundation
import AppKit
import SwiftUI

// MARK: - Ad Models

enum AdType: String, Codable {
    case text
    case banner
}

struct AdContent: Codable, Identifiable {
    var id: String { "\(sponsor)-\(url)" }
    let type: AdType?         // "text" or "banner", defaults to text
    let text: String?          // Text ad copy (type=text)
    let sponsor: String
    let url: String
    let ctaText: String?       // Button text (type=text)
    let bannerURL: String?     // Image URL for banner ads (type=banner)
    let countries: [String]?   // Country codes ["US","GB"] or ["*"] for all

    var resolvedType: AdType { type ?? .text }

    /// Check if this ad should show for a given country code
    func matchesCountry(_ code: String) -> Bool {
        guard let countries = countries, !countries.isEmpty else { return true }
        return countries.contains("*") || countries.contains(code.uppercased())
    }
}

struct AdsPayload: Codable {
    let ads: [AdContent]
}

// MARK: - Ad Service

class AdService: ObservableObject {
    static let shared = AdService()

    private static let adEndpoints = [
        "https://service.h4ux.com/ads-service",
        "https://billowing-term-c225.alon-f46.workers.dev/ads",
        "https://h4ux.github.io/Tickr/ads.json",
    ]

    @Published var currentAd: AdContent
    @Published var bannerImage: NSImage?

    private var allAds: [AdContent] = []
    private var imageCache: [String: NSImage] = [:]
    private var userCountry: String

    private static let defaultAd = AdContent(
        type: .text,
        text: "Remove ads and support Tickr development",
        sponsor: "Tickr Pro",
        url: "",
        ctaText: "Get License",
        bannerURL: nil,
        countries: ["*"]
    )

    private static let countryKey = "userCountryCode"

    // Country detection via Cloudflare Worker.
    // The Worker reads request.cf.country server-side (trusted, can't be spoofed)
    // and returns the 2-letter country code as the response body.
    // Fallback: ipapi.co → system locale
    private static let geoEndpoints = [
        "https://service.h4ux.com/geo-service",
        "https://billowing-term-c225.alon-f46.workers.dev",
    ]

    private init() {
        self.userCountry = UserDefaults.standard.string(forKey: Self.countryKey)
            ?? Locale.current.region?.identifier ?? "US"
        self.currentAd = Self.defaultAd
        detectCountryThenFetchAds(endpointIndex: 0)
    }

    private func detectCountryThenFetchAds(endpointIndex: Int) {
        guard endpointIndex < Self.geoEndpoints.count,
              let url = URL(string: Self.geoEndpoints[endpointIndex]) else {
            fetchAds(); return
        }

        var request = URLRequest(url: url)
        request.setValue(Secrets.geoWorkerKey, forHTTPHeaderField: "X-Tickr-Key")
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let http = response as? HTTPURLResponse

            // Check if we got a valid 2-letter country code
            if let data = data, http?.statusCode == 200,
               let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               code.count == 2, code != "XX" {
                UserDefaults.standard.set(code, forKey: Self.countryKey)
                DispatchQueue.main.async { self?.userCountry = code }
                self?.fetchAds()
            } else {
                // Fallback to next endpoint
                self?.detectCountryThenFetchAds(endpointIndex: endpointIndex + 1)
            }
        }.resume()
    }

    func fetchAds() {
        fetchAdsFromEndpoint(index: 0)
    }

    private func fetchAdsFromEndpoint(index: Int) {
        guard index < Self.adEndpoints.count,
              let url = URL(string: Self.adEndpoints[index]) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            let http = response as? HTTPURLResponse

            if let data = data, http?.statusCode == 200,
               let payload = try? JSONDecoder().decode(AdsPayload.self, from: data),
               !payload.ads.isEmpty {
                let matching = payload.ads.filter { $0.matchesCountry(self.userCountry) }
                DispatchQueue.main.async {
                    self.allAds = matching.isEmpty ? payload.ads : matching
                    self.rotateAd()
                }
            } else {
                // Fallback to next endpoint
                self.fetchAdsFromEndpoint(index: index + 1)
            }
        }.resume()
    }

    func rotateAd() {
        guard !allAds.isEmpty else { return }
        currentAd = allAds.randomElement() ?? Self.defaultAd
        bannerImage = nil

        // If banner ad, fetch the image
        if currentAd.resolvedType == .banner, let bannerURL = currentAd.bannerURL {
            fetchBannerImage(bannerURL)
        }
    }

    private func fetchBannerImage(_ urlString: String) {
        // Check cache
        if let cached = imageCache[urlString] {
            DispatchQueue.main.async { self.bannerImage = cached }
            return
        }

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else { return }
            self?.imageCache[urlString] = image
            DispatchQueue.main.async {
                self?.bannerImage = image
            }
        }.resume()
    }
}
