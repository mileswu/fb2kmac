//
//  TitlebarView.m
//  fb2kmac
//
//  Created by Miles Wu on 14/08/2012.
//
//

#import "TitlebarViewNS.h"
#import "TitlebarButtonNS.h"
#import "TitlebarSeekButtonNS.h"
#import "WindowView.h"
#import "PlaylistView.h"
#import "Playlist.h"

@implementation TitlebarViewNS
@synthesize musicController = _musicController;

- (id)initWithMusicController:(MusicController *)mc {
    if(self = [super init]) {
        _musicController = mc;
        [self updatePlayButtonState];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePlayButtonState:) name:@"startedPlayback" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePlayButtonState:) name:@"stoppedPlayback" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePlayButtonState:) name:@"unpausedPlayback" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePlayButtonState:) name:@"pausedPlayback" object:nil];
        
        TitlebarButtonNS *b = [[TitlebarButtonNS alloc] initWithFrame:NSMakeRect(150, 6, 28, 28)];
        [b setButtonType:NSMomentaryLightButton];
        [b setTarget:self];
        [b setAction:@selector(playButtonPressed:)];
        [b setDrawIcon: [self playButtonDrawBlock]];

        TitlebarSeekButtonNS *c = [[TitlebarSeekButtonNS alloc] initWithFrame:NSMakeRect(180, 6, 28, 28)];
        [c setButtonType:NSMomentaryLightButton];
        [c setTarget:self];
        [c setType:FFSeekButton];
        [c setAction:@selector(nextButtonPressed:)];
        [c setDrawIcon: [self seekButtonDrawBlock:[c getType]]];
        
        TitlebarSeekButtonNS *d = [[TitlebarSeekButtonNS alloc] initWithFrame:NSMakeRect(120, 6, 28, 28)];
        [d setButtonType:NSMomentaryLightButton];
        [d setTarget:self];
        [d setType:RWSeekButton];
        [d setAction:@selector(prevButtonPressed:)];
        [d setDrawIcon: [self seekButtonDrawBlock:[d getType]]];
        
        [self addSubview:b];
        [self addSubview:c];
        [self addSubview:d];
    }
    return self;
}

-(void)updatePlayButtonState:(NSNotification *)notification
{
    [self updatePlayButtonState];
}

-(void)updatePlayButtonState
{
    if([_musicController status] == MusicControllerPlaying)
        _playing = true;
    else
        _playing = false;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect
{
    CGRect b = [self bounds];
	CGContextRef ctx = TUIGraphicsGetCurrentContext();

    int isActive = [[self window] isMainWindow] && [[NSApplication sharedApplication] isActive];
    
    float r = 4;
    CGContextMoveToPoint(ctx, NSMinX(b), NSMinY(b));
    CGContextAddLineToPoint(ctx, NSMinX(b), NSMaxY(b)-r);
    CGContextAddArcToPoint(ctx, NSMinX(b), NSMaxY(b), NSMinX(b)+r, NSMaxY(b), r);
    CGContextAddLineToPoint(ctx, NSMaxX(b)-r, NSMaxY(b));
    CGContextAddArcToPoint(ctx, NSMaxX(b), NSMaxY(b), NSMaxX(b), NSMaxY(b)-r, r);
    CGContextAddLineToPoint(ctx, NSMaxX(b), NSMinY(b));
    CGContextAddLineToPoint(ctx, NSMinX(b), NSMinY(b));
    CGContextSaveGState(ctx);
    CGContextClip(ctx);
    
    TUIColor *gradientStartColor, *gradientEndColor;
    if(isActive) {
        gradientStartColor = [TUIColor colorWithWhite:0.71 alpha:1.0];
        gradientEndColor = [TUIColor colorWithWhite:0.90 alpha:1.0];
    }
    else {
        gradientStartColor = [TUIColor colorWithWhite:0.80 alpha:1.0];
        gradientEndColor = [TUIColor colorWithWhite:0.86 alpha:1.0];
    }
    
    NSArray *colors = [NSArray arrayWithObjects: (id)[gradientStartColor CGColor],
                       (id)[gradientEndColor CGColor], nil];
    CGFloat locations[] = { 0.0, 1.0 };
    CGGradientRef gradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)colors, locations);
    
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(b.origin.x, b.origin.y), CGPointMake(b.origin.x, b.origin.y+b.size.height), 0);
    CGContextRestoreGState(ctx);

    CGGradientRelease(gradient);
    
    [super drawRect:b];
}

-(NSViewDrawRect)playButtonDrawBlock
{
    return ^(NSView *v, CGRect rect) {
        CGContextRef ctx = TUIGraphicsGetCurrentContext();
        CGRect b = v.bounds;
        CGPoint middle = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
        CGContextSaveGState(ctx);

        float size = 9.0;
        float gradient_height;
        
        if(_playing) {
            float height = size*sqrt(3.0), width = 5, seperation = 3;
            CGPoint middle = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
            CGRect rects[] = {
                CGRectMake(middle.x - seperation/2.0 - width, middle.y - height/2.0, width, height),
                CGRectMake(middle.x + seperation/2.0, middle.y - height/2.0, width, height)
            };
            CGContextClipToRects(ctx, rects, 2);
            gradient_height = height/2.0;
        } else {
            float size = 9;
            CGPoint playPoints[] =
            {
                CGPointMake(middle.x + size, middle.y),
                CGPointMake(middle.x - size*0.5, middle.y + size*sqrt(3.0)*0.5),
                CGPointMake(middle.x - size*0.5, middle.y - size*sqrt(3.0)*0.5),
                CGPointMake(middle.x + size, middle.y)
            };
            CGAffineTransform trans = CGAffineTransformMakeTranslation(-1,0);
            for (int i=0; i<4; i++) {
                playPoints[i] = CGPointApplyAffineTransform(playPoints[i],trans);
            }
            CGContextAddLines(ctx, playPoints, 4);
            gradient_height = size*sqrt(3)*0.5;
            CGContextClip(ctx);
        }
        TUIColor *gradientEndColor = [TUIColor colorWithWhite:0.15 alpha:1.0];
        TUIColor *gradientStartColor = [TUIColor colorWithWhite:0.45 alpha:1.0];
        
        NSArray *colors = [NSArray arrayWithObjects: (id)[gradientStartColor CGColor],
                           (id)[gradientEndColor CGColor], nil];
        CGFloat locations[] = { 0.0, 1.0 };
        CGGradientRef gradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)colors, locations);
        
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(middle.x, middle.y + gradient_height), CGPointMake(middle.x, middle.y - gradient_height), 0);
        CGGradientRelease(gradient);
        CGContextRestoreGState(ctx);
    };
}

-(NSViewDrawRect)seekButtonDrawBlock:(SeekButtonDirection)buttonType
{
    float h = 3;
    float l = h*sqrt(3);
    float w = 4;
    float gradient_height = h+w*sqrt(2)*0.5;
    CGAffineTransform trans;
    CGAffineTransform trans2;
    if(buttonType == RWSeekButton) {
        trans = CGAffineTransformMakeTranslation(-3.5,0);
        trans2 = CGAffineTransformMakeTranslation(10,0);
    } else {
        trans = CGAffineTransformMakeTranslation(-6,0);
        trans2 = CGAffineTransformMakeTranslation(10,0);
    }
    return ^(NSView *v, CGRect rect) {
        CGContextRef ctx = TUIGraphicsGetCurrentContext();
        CGRect c = v.bounds;
        CGPoint middle = CGPointMake(CGRectGetMidX(c), CGRectGetMidY(c));
        CGContextSaveGState(ctx);
        
        CGPoint seekPoints[] =
        {
            CGPointMake(middle.x, middle.y),
            CGPointMake(middle.x-l, middle.x-h),
            CGPointMake(middle.x-l+w*sqrt(2)*0.5, middle.y-h-w*sqrt(2)*0.5),
            CGPointMake(middle.x+2*w, middle.y),
            CGPointMake(middle.x-l+w*sqrt(2)*0.5, middle.y+h+w*sqrt(2)*0.5),
            CGPointMake(middle.x-l, middle.y+h),
            CGPointMake(middle.x, middle.y)
        };
        CGPoint seekPoints2[7];
        CGAffineTransform mirror;

        if(buttonType == RWSeekButton){
            mirror = CGAffineTransformTranslate(CGAffineTransformMakeScale(-1, 1),-2*middle.x,0);
        } else {
            mirror = CGAffineTransformMakeTranslation(0,0);
        }
        
        for (int i=0; i<7; i++) {
            seekPoints[i] = CGPointApplyAffineTransform(seekPoints[i],mirror);
            seekPoints[i] = CGPointApplyAffineTransform(seekPoints[i],trans);
            seekPoints2[i] = CGPointApplyAffineTransform(seekPoints[i],trans2);
        }
        
        CGContextAddLines(ctx, seekPoints, 7);
        CGContextAddLines(ctx, seekPoints2, 7);
        
        CGContextClip(ctx);
        
        TUIColor *gradientEndColor = [TUIColor colorWithWhite:0.15 alpha:1.0];
        TUIColor *gradientStartColor = [TUIColor colorWithWhite:0.45 alpha:1.0];
        
        NSArray *colors = [NSArray arrayWithObjects: (id)[gradientStartColor CGColor],
                           (id)[gradientEndColor CGColor], nil];
        CGFloat locations[] = { 0.0, 1.0 };
        CGGradientRef gradient = CGGradientCreateWithColors(NULL, (__bridge CFArrayRef)colors, locations);
        
        CGContextDrawLinearGradient(ctx, gradient, CGPointMake(middle.x, middle.y + gradient_height), CGPointMake(middle.x, middle.y - gradient_height), 0);
        CGGradientRelease(gradient);
        CGContextRestoreGState(ctx);
    };
}

-(void)playButtonPressed:(id)sender
{
    if(_playing) {
        [_musicController pause];
    }
    else {
        if([_musicController status] == MusicControllerPaused) {
            [_musicController unpause];
        }
        else {
            WindowView *wv = (WindowView *)[[[self window] contentView] rootView];
            Playlist *p = [[wv playlistView] playlist];
            if([p numberOfTracks] > 0) {
                [p playTrackAtIndex:0];
            }
        }
    }
}

-(void)prevButtonPressed:(id)sender {
    WindowView *wv = (WindowView *)[[[self window] contentView] rootView];
    Playlist *p = [[wv playlistView] playlist];
    NSUInteger trackIndex = [p getTrackIndex:[_musicController getCurrentTrack]];
    [_musicController stop];
    NSLog(@"%lu",trackIndex);
    if(trackIndex != NSNotFound && trackIndex != 0) {
        NSLog(@"Next song.");
        [p playTrackAtIndex:--trackIndex];
    }
}

-(void)nextButtonPressed:(id)sender {
    WindowView *wv = (WindowView *)[[[self window] contentView] rootView];
    Playlist *p = [[wv playlistView] playlist];
    NSUInteger trackIndex = [p getTrackIndex:[_musicController getCurrentTrack]];
    [_musicController stop];
    NSLog(@"%lu",trackIndex);
    if(trackIndex != NSNotFound && trackIndex != [p numberOfTracks]-1) {
        NSLog(@"Next song.");
        [p playTrackAtIndex:++trackIndex];
    }
}

@end