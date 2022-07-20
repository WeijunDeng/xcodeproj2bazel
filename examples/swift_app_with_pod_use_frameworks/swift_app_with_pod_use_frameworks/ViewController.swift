//
//  ViewController.swift
//  swift_app_with_pod_use_frameworks
//
//  Created by wage on 2022/7/20.
//

import UIKit
import Kingfisher
import MJExtension

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

