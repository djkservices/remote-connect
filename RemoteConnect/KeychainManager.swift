import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    private let serviceName = "com.djkapp.RemoteConnect"

    private init() {}

    func savePassword(_ password: String, for server: Server) {
        let account = "\(server.serverType.rawValue):\(server.username)@\(server.host):\(server.port)"
        guard let data = password.data(using: .utf8) else { return }

        // Delete existing
        deletePassword(for: server)

        // Add new
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func getPassword(for server: Server) -> String? {
        let account = "\(server.serverType.rawValue):\(server.username)@\(server.host):\(server.port)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    func deletePassword(for server: Server) {
        let account = "\(server.serverType.rawValue):\(server.username)@\(server.host):\(server.port)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
