import Foundation

/// Community-data service for the independently maintained repository.
///
/// Supporter data is repository-local so the app does not depend on the
/// upstream project's static data. Contributors come from this fork.
actor SponsorsService {
    private let sponsorsURL = URL(string: "https://raw.githubusercontent.com/mumu-140/port-manager/main/sponsors.json")!
    private let contributorsURL = URL(string: "https://api.github.com/repos/mumu-140/port-manager/contributors")!

    enum SponsorsError: Error, LocalizedError, Sendable {
        case networkError(String)
        case invalidResponse
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .networkError(let description):
                return L("sponsor.error.network", description)
            case .invalidResponse:
                return L("sponsor.error.invalidResponse")
            case .decodingError(let description):
                return L("sponsor.error.decoding", description)
            }
        }
    }

    func fetchSponsors() async throws -> [Sponsor] {
        let (data, response) = try await URLSession.shared.data(from: sponsorsURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SponsorsError.invalidResponse
        }
        do {
            return try JSONDecoder().decode([Sponsor].self, from: data)
        } catch {
            throw SponsorsError.decodingError(error.localizedDescription)
        }
    }

    func fetchContributors() async throws -> [Contributor] {
        var request = URLRequest(url: contributorsURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SponsorsError.invalidResponse
        }
        do {
            return try JSONDecoder().decode([Contributor].self, from: data)
        } catch {
            throw SponsorsError.decodingError(error.localizedDescription)
        }
    }
}
