//
//  SliderBar.m
//  fb2kmac
//
//  Created by Miles Wu on 11/10/2012.
//
//

#import "SliderBar.h"

@implementation SliderBar

@synthesize percentage = _percentage;
@synthesize drawHandle = _drawHandle;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _percentage = 0.0;
        _hoverPercentage = -1.0;
    }
    
    // Mouse tracking for hovers
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:[self bounds] options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];
    
    return self;
}

-(float)convertMouseEventToPercentage:(NSEvent *)event
{
    NSPoint event_location = [event locationInWindow];
    NSPoint local_point = [self convertPoint:event_location fromView:nil];
    float p = local_point.x / [self bounds].size.width;

    return p;
}

-(void)mouseEntered:(NSEvent *)event
{
    NSPoint event_location = [event locationInWindow];
    NSPoint screen_location = [[self window] convertBaseToScreen:event_location];
    NSLog(@"entered at %f %f", screen_location.x, screen_location.y);
    
    float width = 40;
    float height = 50;
    NSRect contentRect = NSMakeRect(0, 0, width, height);
    NSRect frame = contentRect;
    
    _hoverWindow = [[NSWindow alloc] initWithContentRect: contentRect
                                               styleMask: NSBorderlessWindowMask
                                                 backing: NSBackingStoreBuffered
                                                   defer: NO];
    [_hoverWindow setHidesOnDeactivate:YES];
    [_hoverWindow setReleasedWhenClosed:NO];
    [_hoverWindow setOpaque:NO];
    [_hoverWindow setIgnoresMouseEvents:YES];
    //[_hoverWindow setAlphaValue:0.80];
    [_hoverWindow setBackgroundColor:[NSColor colorWithDeviceRed:1.0 green:0.96 blue:0.76 alpha:0.0]];
    //[_hoverWindow setHasShadow:YES];
    [_hoverWindow setLevel:NSStatusWindowLevel];
    
    _hoverView = [[SliderBarHoverView alloc] initWithFrame:frame];
    [_hoverWindow setContentView:_hoverView];
    [_hoverWindow orderFront:nil];
    
    [self mouseMoved:event];
}

-(void)mouseExited:(NSEvent *)event
{
    NSPoint event_location = [event locationInWindow];
    NSPoint screen_location = [[self window] convertBaseToScreen:event_location];
    NSLog(@"exited at %f %f", screen_location.x, screen_location.y);

    [_hoverWindow close];
    _hoverWindow = nil;
    _hoverPercentage = -1.0;
    [self setNeedsDisplay:YES];
}

-(void)mouseMoved:(NSEvent *)event
{
    NSPoint event_location = [event locationInWindow];
    NSPoint window_location_of_bottombar = [self convertPoint:NSMakePoint(0.0, 0.0) toView:nil];
    event_location.y = window_location_of_bottombar.y;
    event_location.x -= 0.5*[_hoverWindow frame].size.width;

    NSPoint screen_location = [[self window] convertBaseToScreen:event_location];
    [_hoverWindow setFrameTopLeftPoint:screen_location];

    float p = [self convertMouseEventToPercentage:event];
    _hoverPercentage = p;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
    float p = [self convertMouseEventToPercentage:event];
    NSNumber *percentage = [NSNumber numberWithFloat:p];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"seekTrack" object:percentage];
}

- (void)drawRect:(NSRect)dirtyRect
{    
    CGRect b = [self bounds];
	CGContextRef ctx = TUIGraphicsGetCurrentContext();
    
    // Draw bar
    TUIColor *gradientStartColor, *gradientEndColor;
    gradientStartColor = [TUIColor colorWithWhite:0.77 alpha:1.0];
    gradientEndColor = [TUIColor colorWithWhite:0.82 alpha:1.0];
    
    NSArray *colors = [NSArray arrayWithObjects: (id)[gradientStartColor CGColor],
                       (id)[gradientEndColor CGColor], nil];
    CGFloat locations[] = { 0.0, 1.0 };
    CGGradientRef gradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)colors, locations);

    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(b.origin.x, b.origin.y), CGPointMake(b.origin.x+b.size.width, b.origin.y+b.size.height), 0);
    CGGradientRelease(gradient);
    
    
    // Draw darkened completed area
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 0.2);
    CGRect progressrect = b;
    progressrect.size.width *= _percentage;
    CGContextFillRect(ctx, progressrect);
    
    // Draw inner drop shadow
    CGMutablePathRef shadowpath = CGPathCreateMutable();
    CGPathAddRect(shadowpath, NULL, CGRectInset(b, -10, -10));
    CGPathAddRect(shadowpath, NULL, b);
    CGPathCloseSubpath(shadowpath);
    
    CGContextSaveGState(ctx);
    CGContextAddRect(ctx, b);
    CGContextClip(ctx);
    
    TUIColor *shadowcolor = [TUIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.7];
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -1), 5, [shadowcolor CGColor]);
    CGContextSetRGBFillColor(ctx, 1.0, 0.0, 0.0, 0.5);
    CGContextAddPath(ctx, shadowpath);

    CGContextEOFillPath(ctx);
    CGContextRestoreGState(ctx);
    CGPathRelease(shadowpath);
    
    // Draw Handle
    if(_drawHandle) {
        
    }
}

-(void)setPercentage:(float)percentage {
    _percentage = percentage;
    [self setNeedsDisplay:YES];
}

@end
