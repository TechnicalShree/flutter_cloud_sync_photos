import CoreTelephony
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let networkChannelName = "flutter_cloud_sync_photos/networkState"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: networkChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "isRoaming":
          result(self?.isRoaming() ?? false)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func isRoaming() -> Bool {
    if #available(iOS 12.0, *) {
      let networkInfo = CTTelephonyNetworkInfo()
      if let identifier = networkInfo.dataServiceIdentifier,
         let carriers = networkInfo.serviceSubscriberCellularProviders,
         let carrier = carriers[identifier],
         let carrierName = carrier.carrierName?.lowercased() {
        return carrierName.contains("roaming")
      }
    }
    return false
  }
}
