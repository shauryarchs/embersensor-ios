import Foundation
import MapKit

class APIService {
    // Max retries for transient backend errors (e.g. Cloudflare 1102 Worker exceeded limits)
    private let maxRetries = 2

    func fetchNIFCFires(completion: @escaping ([NIFCFire]) -> Void) {
        fetchNIFCFiresAttempt(attempt: 0, completion: completion)
    }

    private func fetchNIFCFiresAttempt(attempt: Int, completion: @escaping ([NIFCFire]) -> Void) {
        guard let url = URL(string: "https://embersensor.com/api/calfire-fires") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion([]); return }

            let shouldRetry = (error != nil) || self.isTransientError(data: data, response: response)
            if shouldRetry && attempt < self.maxRetries {
                let delay = pow(2.0, Double(attempt)) * 0.5
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.fetchNIFCFiresAttempt(attempt: attempt + 1, completion: completion)
                }
                return
            }

            guard error == nil, let data = data else {
                completion([])
                return
            }

            do {
                let decoded = try JSONDecoder().decode(NIFCResponse.self, from: data)
                completion(decoded.fires)
            } catch {
                print("NIFC decode error:", error)
                completion([])
            }
        }.resume()
    }

    /// Returns true if the response indicates a transient Cloudflare/Worker error worth retrying.
    private func isTransientError(data: Data?, response: URLResponse?) -> Bool {
        if let http = response as? HTTPURLResponse {
            // 5xx and 520-527 (Cloudflare-specific) are retryable
            if http.statusCode >= 500 { return true }
        }
        if let data = data, let body = String(data: data, encoding: .utf8) {
            if body.contains("Error 1102") || body.contains("Worker exceeded resource limits") {
                return true
            }
        }
        return false
    }

    func fetchStatus(forceRefresh: Bool = false, completion: @escaping (FireStatus?) -> Void) {
        fetchStatusAttempt(forceRefresh: forceRefresh, attempt: 0, completion: completion)
    }

    private func fetchStatusAttempt(forceRefresh: Bool, attempt: Int, completion: @escaping (FireStatus?) -> Void) {
        var urlString = "https://embersensor.com/api/status"

        if forceRefresh {
            let ts = Int(Date().timeIntervalSince1970)
            urlString += "?refreshWeather=1&refreshFirms=1&t=\(ts)"
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion(nil); return }

            // Retry on network error or transient backend error
            let shouldRetry = (error != nil) || self.isTransientError(data: data, response: response)

            if shouldRetry && attempt < self.maxRetries {
                let delay = pow(2.0, Double(attempt)) * 0.5 // 0.5s, 1.0s
                print("Status fetch failed (attempt \(attempt + 1)), retrying in \(delay)s")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.fetchStatusAttempt(forceRefresh: forceRefresh, attempt: attempt + 1, completion: completion)
                }
                return
            }

            guard error == nil, let data = data else {
                completion(nil)
                return
            }

            do {
                let decoded = try JSONDecoder().decode(FireStatus.self, from: data)
                completion(decoded)
            } catch {
                print("Decode error:", error)
                completion(nil)
            }
        }.resume()
    }

    func fetchFires(
        region: MKCoordinateRegion,
        forceRefresh: Bool = false,
        completion: @escaping ([FirePoint]) -> Void
    ) {
        fetchFiresAttempt(region: region, forceRefresh: forceRefresh, attempt: 0, completion: completion)
    }

    private func fetchFiresAttempt(
        region: MKCoordinateRegion,
        forceRefresh: Bool,
        attempt: Int,
        completion: @escaping ([FirePoint]) -> Void
    ) {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        var urlString = "https://embersensor.com/api/fires?minLat=\(minLat)&maxLat=\(maxLat)&minLon=\(minLon)&maxLon=\(maxLon)"

        if forceRefresh {
            let ts = Int(Date().timeIntervalSince1970)
            urlString += "&refreshFirms=1&t=\(ts)"
        }

        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { completion([]); return }

            let shouldRetry = (error != nil) || self.isTransientError(data: data, response: response)

            if shouldRetry && attempt < self.maxRetries {
                let delay = pow(2.0, Double(attempt)) * 0.5
                print("Fires fetch failed (attempt \(attempt + 1)), retrying in \(delay)s")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.fetchFiresAttempt(region: region, forceRefresh: forceRefresh, attempt: attempt + 1, completion: completion)
                }
                return
            }

            guard error == nil, let data = data else {
                completion([])
                return
            }

            do {
                let decoded = try JSONDecoder().decode(FiresResponse.self, from: data)
                completion(decoded.fires)
            } catch {
                print("Fires decode error:", error)
                completion([])
            }
        }.resume()
    }
}
