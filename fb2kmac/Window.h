//
//  Window.h
//  fb2kmac
//
//  Created by Miles Wu on 14/08/2012.
//
//
#import "TUIKit.h"
#import <Cocoa/Cocoa.h>

@interface Window : NSWindow {
    NSView *_titlebarView;
}
- (void)relayout;

@end
