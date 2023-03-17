//
//  ReactShareViewController.swift
//  RNShareMenu
//
//  DO NOT EDIT THIS FILE. IT WILL BE OVERRIDEN BY NPM OR YARN.
//
//  Created by Gustavo Parreira on 29/07/2020.
//

import RNShareMenu
import MobileCoreServices

class ReactShareViewController: UIViewController, RCTBridgeDelegate, ReactShareViewDelegate {
  func sourceURL(for bridge: RCTBridge!) -> URL! {
#if DEBUG
    return RCTBundleURLProvider.sharedSettings()?
      .jsBundleURL(forBundleRoot: "index.share", fallbackResource: nil)
#else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
  
  var hostAppId: String?
  var hostAppUrlScheme: String?

  override func viewDidLoad() {
    super.viewDidLoad()
    
    if let hostAppId = Bundle.main.object(forInfoDictionaryKey: HOST_APP_IDENTIFIER_INFO_PLIST_KEY) as? String {
      self.hostAppId = hostAppId
    } else {
      print("Error: \(NO_INFO_PLIST_INDENTIFIER_ERROR)")
    }
    
    if let hostAppUrlScheme = Bundle.main.object(forInfoDictionaryKey: HOST_URL_SCHEME_INFO_PLIST_KEY) as? String {
      self.hostAppUrlScheme = hostAppUrlScheme
    } else {
      print("Error: \(NO_INFO_PLIST_URL_SCHEME_ERROR)")
    }

    let bridge: RCTBridge! = RCTBridge(delegate: self, launchOptions: nil)
    let rootView = RCTRootView(
      bridge: bridge,
      moduleName: "ShareMenuModuleComponent",
      initialProperties: nil
    )

    rootView.backgroundColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    backgroundColorSetup: if let backgroundColorConfig = Bundle.main.infoDictionary?[REACT_SHARE_VIEW_BACKGROUND_COLOR_KEY] as? [String:Any] {
      if let transparent = backgroundColorConfig[COLOR_TRANSPARENT_KEY] as? Bool, transparent {
        rootView.backgroundColor = nil
        break backgroundColorSetup
      }

      let red = backgroundColorConfig[COLOR_RED_KEY] as? Float ?? 1
      let green = backgroundColorConfig[COLOR_GREEN_KEY] as? Float ?? 1
      let blue = backgroundColorConfig[COLOR_BLUE_KEY] as? Float ?? 1
//      let alpha = backgroundColorConfig[COLOR_ALPHA_KEY] as? Float ?? 1
      let alpha = 0

      rootView.backgroundColor = UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    self.view = rootView

    ShareMenuReactView.attachViewDelegate(self)
  }

  override func viewDidDisappear(_ animated: Bool) {
//    cancel()
    ShareMenuReactView.detachViewDelegate()
  }

  func loadExtensionContext() -> NSExtensionContext {
    let ms = 1000
    usleep(useconds_t(300 * ms))
    return extensionContext!
  }

  func openApp() {
    self.openHostApp()
  }

  func continueInApp(with item: NSExtensionItem, and extraData: [String:Any]?) {
    self.handlePost(item, extraData: extraData)
  }
  
  func handlePost(_ item: NSExtensionItem, extraData: [String:Any]? = nil) {
    guard let provider = item.attachments?.first else {
      cancelRequest()
      return
    }

    if let data = extraData {
      storeExtraData(data)
    } else {
      removeExtraData()
    }

    if provider.isText {
      storeText(withProvider: provider)
    } else if provider.isURL {
      storeUrl(withProvider: provider)
    } else {
      self.storeFile(withProvider: provider)
    }
  }
  
  func exit(withError error: String) {
    print("Error: \(error)")
    cancelRequest()
  }
  
  internal func openHostApp() {
    guard let urlScheme = self.hostAppUrlScheme else {
      exit(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }
    
    let url = URL(string: urlScheme)
    let selectorOpenURL = sel_registerName("openURL:")
    var responder: UIResponder? = self
    
    while responder != nil {
      if responder?.responds(to: selectorOpenURL) == true {
        responder?.perform(selectorOpenURL, with: url)
      }
      responder = responder!.next
    }
    
    completeRequest()
  }
  
  func completeRequest() {
    // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
    extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
  }
  
  func cancelRequest() {
    extensionContext!.cancelRequest(withError: NSError())
  }
  
  func storeFile(withProvider provider: NSItemProvider) {
    provider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (data, error) in
      guard (error == nil) else {
        self.exit(withError: error.debugDescription)
        return
      }
      var url:URL! = nil;
      let imgData: UIImage! = data as? UIImage;
      if (imgData != nil) {
        guard let imageURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TemporaryScreenshot.png") else {
            return
        }
        url = imageURL;
      } else {
        guard let currentUrl = data as? URL else {
          self.exit(withError: COULD_NOT_FIND_IMG_ERROR)
          return
        }
        url = currentUrl;
      }
      
      guard let hostAppId = self.hostAppId else {
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }
      guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId).vmoon") else {
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }
      guard let groupFileManagerContainer = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostAppId).vmoon")
      else {
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }
      
      let mimeType = url.extractMimeType()
      let fileExtension = url.pathExtension
      let fileName = UUID().uuidString
      let filePath = groupFileManagerContainer
        .appendingPathComponent("\(fileName).\(fileExtension)")
      
      guard self.moveFileToDisk(from: url, to: filePath) else {
        self.exit(withError: COULD_NOT_SAVE_FILE_ERROR)
        return
      }
      
      userDefaults.set([DATA_KEY: filePath.absoluteString,  MIME_TYPE_KEY: mimeType],
                       forKey: USER_DEFAULTS_KEY)
      userDefaults.synchronize()
      
      self.openHostApp()
    }
  }
  
  func storeExtraData(_ data: [String:Any]) {
    guard let hostAppId = self.hostAppId else {
      print("Error: \(NO_INFO_PLIST_INDENTIFIER_ERROR)")
      return
    }
    guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId).vmoon") else {
      print("Error: \(NO_APP_GROUP_ERROR)")
      return
    }
    userDefaults.set(data, forKey: USER_DEFAULTS_EXTRA_DATA_KEY)
    userDefaults.synchronize()
  }
  
  func removeExtraData() {
    guard let hostAppId = self.hostAppId else {
      print("Error: \(NO_INFO_PLIST_INDENTIFIER_ERROR)")
      return
    }
    guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId).vmoon") else {
      print("Error: \(NO_APP_GROUP_ERROR)")
      return
    }
    userDefaults.removeObject(forKey: USER_DEFAULTS_EXTRA_DATA_KEY)
    userDefaults.synchronize()
  }
  
  func moveFileToDisk(from srcUrl: URL, to destUrl: URL) -> Bool {
    do {
      if FileManager.default.fileExists(atPath: destUrl.path) {
        try FileManager.default.removeItem(at: destUrl)
      }
      try FileManager.default.copyItem(at: srcUrl, to: destUrl)
    } catch (let error) {
      print("Could not save file from \(srcUrl) to \(destUrl): \(error)")
      return false
    }
    
    return true
  }
  
  func storeText(withProvider provider: NSItemProvider) {
    provider.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil) { (data, error) in
      guard (error == nil) else {
        self.exit(withError: error.debugDescription)
        return
      }
      guard let text = data as? String else {
        self.exit(withError: COULD_NOT_FIND_STRING_ERROR)
        return
      }
      guard let hostAppId = self.hostAppId else {
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }
      guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId).vmoon") else {
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }
      
      userDefaults.set([DATA_KEY: text, MIME_TYPE_KEY: "text/plain"],
                       forKey: USER_DEFAULTS_KEY)
      userDefaults.synchronize()
      
      self.openHostApp()
    }
  }
  
  func storeUrl(withProvider provider: NSItemProvider) {
    provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (data, error) in
      guard (error == nil) else {
        self.exit(withError: error.debugDescription)
        return
      }
      guard let url = data as? URL else {
        self.exit(withError: COULD_NOT_FIND_URL_ERROR)
        return
      }
      guard let hostAppId = self.hostAppId else {
        self.exit(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
        return
      }
      guard let userDefaults = UserDefaults(suiteName: "group.\(hostAppId).vmoon") else {
        self.exit(withError: NO_APP_GROUP_ERROR)
        return
      }
      
      userDefaults.set([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: "text/plain"],
                       forKey: USER_DEFAULTS_KEY)
      userDefaults.synchronize()
      
      self.openHostApp()
    }
  }
}
