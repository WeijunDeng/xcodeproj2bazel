//
//  ViewController.m
//  app_and_library_dead_code
//
//  Created by dengweijun on 2022/8/24.
//

#import "ViewController.h"
#import "dynamic_framework_b.h"
#import "dynamic_framework_d.h"
#import "static_framework_c_bye.h"
#import "static_framework_c_hello.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    dynamic_framework_b_hello();
    dynamic_framework_d_bye();
    static_framework_c_bye();
    static_framework_c_hello();
}


@end
