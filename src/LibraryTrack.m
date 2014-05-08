//
//  Track.m
//  dokibox
//
//  Created by Miles Wu on 10/02/2013.
//
//

#import "LibraryTrack.h"
#import "LibraryArtist.h"
#import "LibraryAlbum.h"
#import "CoreDataManager.h"

@implementation LibraryTrack
@dynamic album;
@dynamic trackNumber;
@dynamic length;

-(void)didTurnIntoFault {
    //NSLog(@"hi turned into fault");
    [super didTurnIntoFault];
}

-(void)setArtistByName:(NSString *)artistName andAlbumByName:(NSString *)albumName
{
    NSError *error;
    LibraryAlbum *album;
    LibraryAlbum *oldAlbum = [self album];

    NSFetchRequest *fr = [NSFetchRequest fetchRequestWithEntityName:@"album"];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(name == %@) AND (artist.name == %@)", albumName, artistName];
    [fr setPredicate:predicate];

    NSArray *results = [[self managedObjectContext] executeFetchRequest:fr error:&error];
    if(results == nil) {
        NSLog(@"error fetching results");
    }
    else if([results count] == 0) {
        album = [NSEntityDescription insertNewObjectForEntityForName:@"album" inManagedObjectContext:[self managedObjectContext]];
        [album setName:albumName];
        [album setArtistByName:artistName];
    }
    else { //already exists in library
        album = [results objectAtIndex:0];
    }
    
    if(oldAlbum != album) { //prune old one
        [oldAlbum pruneDueToTrackBeingDeleted:self];
    }

    [self setAlbum:album];
}

-(void)prepareForDeletion
{
    [[self album] pruneDueToTrackBeingDeleted:self];
}



@end
