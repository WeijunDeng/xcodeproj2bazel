//
//  dynamic_framework_b.c
//  dynamic_framework_b
//
//  Created by dengweijun on 2022/8/24.
//

#include <stdio.h>
#import "static_framework_c_hello.h"

void dynamic_framework_b_hello(void) {
    printf("dynamic_framework_d_hello");
    static_framework_c_hello();
}
