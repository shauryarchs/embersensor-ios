import Foundation

class APIService {
    func fetchStatus(forceRefresh: Bool = false, completion: @escaping (FireStatus?) -> Void) {
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

        URLSession.shared.dataTask(with: request) { data, _, error in
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
}
