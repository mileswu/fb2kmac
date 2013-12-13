//
//  TitlebarView.h
//  dokibox
//
//  Created by Miles Wu on 14/08/2012.
//
//

#import <Cocoa/Cocoa.h>
#import "MusicController.h"
#import "PlaylistTrack.h"
#import "SliderBar.h"
#import "TitlebarSeekButtonNS.h"

@class SPMediaKeyTap;

@interface TitlebarViewNS : NSView <SliderBarDelegate> {
    BOOL _playing;
    MusicController *_musicController;

    NSString *_title;
    NSString *_artist;

    SliderBar *_progressBar;
    NSDictionary *_progressDict;

    SliderBar *_volumeBar;
    
    SPMediaKeyTap *_keyTap;
}

-(id)initWithMusicController:(MusicController *)mc;
-(void)initSubviews;
-(NSViewDrawRect)playButtonDrawBlock;
-(NSViewDrawRect)seekButtonDrawBlock:(SeekButtonDirection)buttonType;
-(void)playButtonPressed:(id)sender;
-(void)nextButtonPressed:(id)sender;
-(void)prevButtonPressed:(id)sender;
-(void)updatePlayButtonState:(NSNotification *)notification;
-(void)updatePlayButtonState;

-(void)receivedStartedPlaybackNotification:(NSNotification *)notification;
-(void)receivedPlaybackProgressNotification:(NSNotification *)notification;

@property MusicController *musicController;


@end
