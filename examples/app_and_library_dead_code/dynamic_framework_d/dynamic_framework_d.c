//
//  dynamic_framework_d.c
//  dynamic_framework_d
//
//  Created by dengweijun on 2022/8/24.
//

#include <stdio.h>
#import "dynamic_framework_b.h"
#import "static_framework_c_bye.h"
#import "static_framework_c_hello.h"

void dynamic_framework_d_bye(void) {
    printf("dynamic_framework_d_bye");
    dynamic_framework_b_hello();
    static_framework_c_bye();
    static_framework_c_hello();
}
