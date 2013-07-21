//
//  NSView+CGDrawing.h
//  fb2kmac
//
//  Created by Miles Wu on 20/07/2013.
//
//

#import <Cocoa/Cocoa.h>

@interface NSView (CGDrawing)

- (void)CGContextRoundedCornerPath:(CGRect)b context:(CGContextRef)ctx radius:(CGFloat)r withHalfPixelRedution:(BOOL)onpixel;

@end