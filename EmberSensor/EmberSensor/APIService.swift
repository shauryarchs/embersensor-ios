import Foundation

class APIService {
    
    func fetchStatus(completion: @escaping (FireStatus?) -> Void) {
        
        guard let url = URL(string: "https://embersensor.com/api/status") else {
            completion(nil)
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                let result = try? JSONDecoder().decode(FireStatus.self, from: data)
                
                DispatchQueue.main.async {
                    completion(result)
                }
                
            } catch {
                print("API Error:", error)
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
