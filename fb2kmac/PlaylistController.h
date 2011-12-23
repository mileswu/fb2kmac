//
//  PlaylistController.h
//  fb2kmac
//
//  Created by Miles Wu on 20/11/2011.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "common.h"

@interface PlaylistController : NSObject <NSApplicationDelegate> {
    NSMutableArray *trackArray;
    int currentPlayingTrackIndex;
    
    IBOutlet NSTableView *playlistTableView;
    IBOutlet NSArrayController *playlistArrayController;
    IBOutlet MusicController *musicController;
}

@property (retain) NSMutableArray *trackArray;

// Initialization
- (id)init;
- (void)awakeFromNib;

// Dragging operations
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op;
- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id)info row:(int)row dropOperation:(NSTableViewDropOperation)op;
- (IBAction)deleteButtonPressed:(id)sender;

// Double click
- (void)trackDoubleClicked:(id)sender;

- (PlaylistTrack *)getCurrentTrack;

@end
