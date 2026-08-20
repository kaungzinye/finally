import Foundation

struct FinallyServerWorkspaceConfiguration: Codable {
    var baseURL: String?
    var projectID: Int64?
}

extension UserSession {
    var finallyServerConfiguration: FinallyServerWorkspaceConfiguration {
        get {
            guard providerIdentity == .finallyServer,
                  let providerConfigurationData,
                  let configuration = try? JSONDecoder().decode(
                      FinallyServerWorkspaceConfiguration.self,
                      from: providerConfigurationData
                  ) else { return FinallyServerWorkspaceConfiguration() }
            return configuration
        }
        set {
            providerConfigurationData = try? JSONEncoder().encode(newValue)
        }
    }

    var serverBaseURL: String? {
        get { finallyServerConfiguration.baseURL }
        set {
            var configuration = finallyServerConfiguration
            configuration.baseURL = newValue
            finallyServerConfiguration = configuration
        }
    }

    var serverProjectID: Int64? {
        get { finallyServerConfiguration.projectID }
        set {
            var configuration = finallyServerConfiguration
            configuration.projectID = newValue
            finallyServerConfiguration = configuration
        }
    }
}
