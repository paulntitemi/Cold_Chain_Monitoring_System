import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Read the Google Maps API key from Info.plist so we do not have to
    // hardcode it in source. The key is injected into Info.plist via the
    // `GoogleMapsApiKey` entry — see ios/Runner/Info.plist.
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
       !apiKey.isEmpty,
       apiKey != "your_key_here" {
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("[ColdTrack] Google Maps API key not configured — map screen will show a fallback.")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
