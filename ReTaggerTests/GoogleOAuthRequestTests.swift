import Testing
import Foundation
@testable import ReTagger

struct GoogleOAuthRequestTests {
    @Test func googlePayloadBindsRegistrationAndClientWithPkce() throws {
        let request = NativeOAuthRequest(registrationId: "retagger-google-macos-prod", clientId: "desktop.apps.googleusercontent.com",
            code: "code", redirectUri: "http://127.0.0.1:1234/oauth2redirect", codeVerifier: "verifier")
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(payload["registrationId"] as? String == "retagger-google-macos-prod")
        #expect(payload["clientId"] as? String == "desktop.apps.googleusercontent.com")
        #expect(payload["usePkce"] as? Bool == true)
        #expect(payload["codeVerifier"] as? String == "verifier")
        #expect(payload["registrationSource"] as? String == "retagger")
    }

    @Test func applePayloadDoesNotIncludeGoogleBinding() throws {
        let request = NativeOAuthRequest(code: "apple-code", usePkce: false)
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(payload["provider"] as? String == "apple")
        #expect(payload["registrationId"] == nil)
        #expect(payload["codeVerifier"] == nil)
        #expect(payload["registrationSource"] as? String == "retagger")
    }

    @Test func loginRequestPayloadIncludesDefaultRegistrationSource() throws {
        let request = LoginRequest(email: "test@example.com", password: "password123")
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(payload["email"] as? String == "test@example.com")
        #expect(payload["password"] as? String == "password123")
        #expect(payload["registrationSource"] as? String == "retagger")
    }
}
