//
//  MP3Decoder.h
//  fb2kmac
//
//  Created by Miles Wu on 22/11/2011.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DecoderProtocol.h"
#import "common.h"
#include <mpg123.h>

@interface MP3Decoder : NSObject<DecoderProtocol> {
    mpg123_handle *mh;
    MusicController *musicController;
    DecoderMetadata _metadata;
}

@property (retain) MusicController *musicController;


@end