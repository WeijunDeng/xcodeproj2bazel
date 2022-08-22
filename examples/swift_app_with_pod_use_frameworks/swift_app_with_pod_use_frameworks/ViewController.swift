//
//  ViewController.swift
//  swift_app_with_pod_use_frameworks
//
//  Created by dengweijun on 2022/7/20.
//

import UIKit

import AFNetworking
import AgoraRtcKit
import Alamofire
import AliyunOSSiOS
import AMPopTip
import AMScrollingNavbar
import AnimatedCollectionViewLayout
import AnyImageKit
import Aspects
import AsyncDisplayKit
import Bagel
import BarcodeScanner
import Base64
import BlocksKit
import BLTNBoard
import Bugly
import Cartography
import Charts
import CocoaAsyncSocket
import CocoaLumberjack
import CoconutKit
import CryptoSwift
import DropDown
import Eureka
import FBAEMKit
import FBAllocationTracker
import FBLPromises
import FBMemoryProfiler
import FBRetainCycleDetector
import FBSDKCoreKit_Basics
import FDFullscreenPopGesture
import FileKit
import FirebaseAnalytics
import FirebaseAuth
import FirebaseCore
import FirebaseCoreDiagnostics
import FirebaseCoreInternal
import FirebaseCrashlytics
import FirebaseInstallations
import fishhook
import FLAnimatedImage
import FLEX
import FMDB
import FSCalendar
import FSPagerView
import GoogleDataTransport
import GoogleUtilities
import GrowingAutoTrackKit
import GrowingCoreKit
import GTMSessionFetcher
import InAppPurchase
import InputBarAccessoryView
import Instructions
import IQKeyboardManager
import JLRoutes
import JRSwizzle
import JTAppleCalendar
import JWT
import JXPagingView
import JXSegmentedView
import KeychainAccess
import Kingfisher
import KingfisherWebP
import Koloda
import Lantern
import libwebp
import Loading
import LookinServer
import Lottie
import LTMorphingLabel
import Macaw
import Masonry
import Material
import MBProgressHUD
import MJExtension
import MJRefresh
import MLeaksFinder
import MMKV
import MMKVCore
import MonkeyKing
import Motion
import Moya
import MTAppenderFile
import MTHawkeye
import nanopb
import NSAttributedStringBuilder13
import Nuke
import NVActivityIndicatorView
import ObjectMapper
import OHHTTPStubs
import PanModal
import Permission
import PhoneNumberKit
import PINCache
import PINOperation
import PINRemoteImage
import pop
import PPBadgeViewSwift
import PromiseKit
import QMUIKit
import Reachability
import ReactiveObjC
import Realm
import RealmSwift
import ReSwift
import RevealServer
import Rswift
import RxCocoa
import RxRelay
import RxSwift
import SDWebImage
import Sentry
import SideMenu
import Siren
import SkeletonView
import SnapKit
import SQLite
import Starscream
import Surge
import SVProgressHUD
import swift_app_with_pod_use_frameworks
import SwiftDate
import SwiftEntryKit
import SwifterSwift
import SwiftMessages
import SwiftRichString
import SwiftyBeaver
import SwiftyJSON
import SwiftyStoreKit
import SwipeCellKit
import SWXMLHash
import TensorFlowLiteTaskText
import TextFieldEffects
import TOCropViewController
import ViewAnimator
import WKWebViewJavascriptBridge
import YYCache
import YYImage
import YYModel
import YYText
import ZipArchive

@objc(MJTester)
@objcMembers
class MJTester: NSObject {
    // make sure to use `dynamic` attribute for basic type & must use as Non-Optional & must set initial value
    dynamic var isSpecialAgent: Bool = false
    dynamic var age: Int = 0
    
    var name: String?
    var identifier: String?
}

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        let imageView = UIImageView()
        let url = URL(string: "https://example.com/image.png")
        imageView.kf.setImage(with: url)
        
        let testerDict: [String: Any] = [
                   "isSpecialAgent": true,
                   "identifier": "007",
                   "age": 22,
                   "name": "Juan"
               ]
               
        let _ = MJTester.mj_object(withKeyValues: testerDict)
        
    }

}

