import Foundation

// Values are injected at build time from Secrets.xcconfig → Info.plist.
// See Secrets.xcconfig.example for setup instructions.
enum ACRCloudConfig {
    static let host: String = Bundle.main.infoDictionary?["ACRCloudHost"] as? String ?? ""
    static let accessKey: String = Bundle.main.infoDictionary?["ACRCloudAccessKey"] as? String ?? ""
    static let accessSecret: String = Bundle.main.infoDictionary?["ACRCloudAccessSecret"] as? String ?? ""
}
