//
//  ViewController.swift
//  swift_app_with_pod_no_use_frameworks
//
//  Created by wage on 2022/7/20.
//

import UIKit
import Kingfisher

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        let imageView = UIImageView()
        let url = URL(string: "https://example.com/image.png")
        imageView.kf.setImage(with: url)
    }

}

