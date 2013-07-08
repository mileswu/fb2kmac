//
//  Playlist.m
//  fb2kmac
//
//  Created by Miles Wu on 28/07/2012.
//
//

#import "Playlist.h"
#import "MusicController.h"

@implementation Playlist

@dynamic name;
@dynamic tracks;

-(NSUInteger)numberOfTracks {
    return [[self tracks] count];
}

-(NSUInteger)getTrackIndex:(PlaylistTrack *)track {
    return [[self tracks] indexOfObject:track];
}

-(PlaylistTrack *)trackAtIndex:(NSUInteger)index {
    return [[self tracks] objectAtIndex:index];
}

-(void)removeTrackAtIndex:(NSUInteger)index {
    [[self tracks] removeObjectAtIndex:index];
    [self save];
}

-(void)insertTrack:(PlaylistTrack *)track atIndex:(NSUInteger)index {
    [[self tracks] insertObject:track atIndex:index];
    [self save];
}

-(void)addTrack:(PlaylistTrack *)track {
    [[self tracks] addObject:track];
    [self save];
}

-(void)save
{
    NSError *error;
    if([[self managedObjectContext] save:&error] == NO) {
        NSLog(@"error saving");
        NSLog(@"%@", [error localizedDescription]);
        for(NSError *e in [[error userInfo] objectForKey:NSDetailedErrorsKey]) {
            NSLog(@"%@", [e localizedDescription]);
        }
    }
}

-(void)playTrackAtIndex:(NSUInteger)index {
    PlaylistTrack *track = [self trackAtIndex:index];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedTrackEndedNotification:) name:@"trackEnded" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"playTrack" object:track];
    
}

-(void)receivedTrackEndedNotification:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"trackEnded" object:nil];
    
    if([notification object] != nil) {
        PlaylistTrack *trackJustEnded = [notification object];
        NSUInteger index = [[self tracks] indexOfObject:trackJustEnded];
        if(index != NSNotFound && index != [self numberOfTracks]-1) {
            index += 1;
            [self playTrackAtIndex:index];
        }
    }
}

@end
