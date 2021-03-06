//
//  MusicController.m
//  dokibox
//
//  Created by Miles Wu on 22/11/2011.
//  Copyright (c) 2015 Miles Wu and contributors. All rights reserved.
//

#import "MusicController.h"
#import "PlaylistTrack.h"
#import "Playlist.h"
#import "plugins/PluginManager.h"

#import <AudioUnit/AudioUnit.h>

#define FIFOBUFFER_TOTAL_SECONDS 20
#define FIFOBUFFER_START_REFILL_SECONDS 12
#define FIFOBUFFER_STOP_REFILL_SECONDS 15

static OSStatus playProc(AudioConverterRef inAudioConverter,
                         UInt32 *ioNumberDataPackets,
                         AudioBufferList *outOutputData,
                         AudioStreamPacketDescription **outDataPacketDescription,
                         void* inClientData) {
    //DDLogCVerbose(@"Number of buffers %d", outOutputData->mNumberBuffers);
    MusicController *mc = (__bridge MusicController *)inClientData;

    int size = *ioNumberDataPackets * [mc inFormat].mBytesPerPacket;

    [[mc fifoBuffer] read:(void *)[[mc auBuffer] bytes] size:&size];

    [mc setElapsedFrames:[mc elapsedFrames] + size/[mc inFormat].mBytesPerFrame];
    
    outOutputData->mNumberBuffers = 1;
    outOutputData->mBuffers[0].mDataByteSize = size;
    outOutputData->mBuffers[0].mData = (void *)[[mc auBuffer] bytes];
    
    static BOOL bufferUnderflowTrip = false;
    if(size == 0) {
        if([mc decoderStatus] == MusicControllerDecodedSong) { // Natural EOF
            dispatch_async(dispatch_get_main_queue(), ^() {
                [mc trackEndedNaturally];
            });
        }
        else {
            if(bufferUnderflowTrip == false) { // Only prints once
                DDLogCWarn(@"Buffer underflow");
                bufferUnderflowTrip = true;
            }
        }
    }
    else {
        bufferUnderflowTrip = false; // Reset trip flag
    }

    // Refill buffer if it falls below FIFOBUFFER_START_REFILL_SECONDS
    size_t stored = [[mc fifoBuffer] stored];
    if(stored < [mc inFormat].mBytesPerFrame*[mc inFormat].mSampleRate*FIFOBUFFER_START_REFILL_SECONDS && [mc decoderStatus] == MusicControllerDecodingSong) {
        dispatch_async([mc decoding_queue], ^{
            [mc fillBuffer];
        });
    }

    return(noErr);

}

static OSStatus renderProc(void *inRefCon, AudioUnitRenderActionFlags *inActionFlags,
                            const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
                            UInt32 inNumFrames, AudioBufferList *ioData)
{
    @autoreleasepool {
        MusicController *mc = (__bridge MusicController *)inRefCon;
        AudioStreamPacketDescription* outPacketDescription = NULL;

        OSStatus err = AudioConverterFillComplexBuffer([mc converter], playProc, inRefCon, &inNumFrames, ioData, outPacketDescription);
        return(err);
    }
}



@implementation MusicController

@synthesize decoding_queue;
@synthesize fifoBuffer;
@synthesize auBuffer;
@synthesize converter;
@synthesize decoderStatus = _decoderStatus;
@synthesize inFormat = _inFormat;
@synthesize elapsedFrames = _elapsedFrames;

+ (BOOL)isSupportedAudioFile:(NSString *)filename
{
    NSString *ext = [[filename pathExtension] lowercaseString];
    if([ext compare:@"flac"] == NSOrderedSame) {
        return YES;
    }
    else if([ext compare:@"mp3"] == NSOrderedSame) {
        return YES;
    }
    else if([ext compare:@"ogg"] == NSOrderedSame) {
        return YES;
    }
    else if([ext compare:@"m4a"] == NSOrderedSame) {
        return YES;
    }
    else {
        return NO;
    }
}

- (id)init {
    self = [super init];
    _decoderStatus = MusicControllerDecoderIdle;
    _status = MusicControllerStopped;
    
    // Retrieve volume
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"volume"]) {
        _volume = [[NSUserDefaults standardUserDefaults] floatForKey:@"volume"];
    }
    else {
        _volume = 1.0;
    }
        
    NSString *queueName = [NSString stringWithFormat:@"%@.decoding", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"]];
    decoding_queue = dispatch_queue_create([queueName cStringUsingEncoding:NSUTF8StringEncoding],NULL);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedPlayTrackNotification:) name:@"playTrack" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedSeekTrackNotification:) name:@"seekTrack" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedSeekTrackNotification:) name:@"seekTrackByJump" object:nil];

    return self;
}

- (void)dealloc
{
    dispatch_release(decoding_queue);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"playTrack" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"seekTrack" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"seekTrackByJump" object:nil];
}

- (void)createOrReconfigureAudioGraph:(DecoderMetadata)decoderMetadata
{
    AUNodeInteraction *connections = NULL;
    UInt32 noconns;
    int err;

    if(_outputGraph == 0) {
        DDLogVerbose(@"Creating audio graph (first-time)");
        [self createAudioGraph];
    }

    Boolean wasinitialized;
    if((err = AUGraphIsInitialized(_outputGraph, &wasinitialized))) {
        DDLogError(@"AUGraphIsInitialized failed");
    }

    if(wasinitialized) {
        // NB. This techincally only really needs to be if sample rate/format has changed, but we do it every time at the moment
        DDLogVerbose(@"Reconfiguring audio graph for new format");

        // Uninitialize graph
        if((err = AUGraphUninitialize(_outputGraph))) {
            DDLogError(@"AUGraphUninitialize failed");
        }

        // Save and clear connections
        if((err = AUGraphGetNumberOfInteractions(_outputGraph, &noconns)))
            DDLogError(@"AUGraphGetNumberofInteractions failed");

        connections = malloc(sizeof(AUNodeInteraction) * noconns);
        for(int i=0; i<noconns; i++) {
            if((err = AUGraphGetInteractionInfo(_outputGraph, i, &connections[i])))
               DDLogError(@"AUGraphGetInteractionInfo failed");
        }
        if((err = AUGraphClearConnections(_outputGraph)))
            DDLogError(@"AUGraphClearConnections failed");

        // Configure graph with new decoderMetadata
        [self configureAudioGraph:decoderMetadata];

        // Restore connections
        for(int i=0; i<noconns; i++) {
            if(connections[i].nodeInteractionType == kAUNodeInteraction_Connection) {
                AUNodeConnection c = connections[i].nodeInteraction.connection;
                if((err = AUGraphConnectNodeInput(_outputGraph, c.sourceNode, c.sourceOutputNumber, c.destNode, c.destInputNumber)))
                    DDLogError(@"AUGraphConnectNodeInput failed");;
            }
            if(connections[i].nodeInteractionType == kAUNodeInteraction_InputCallback) {
                AUNodeRenderCallback c = connections[i].nodeInteraction.inputCallback;
                if((err = AUGraphSetNodeInputCallback(_outputGraph, c.destNode, c.destInputNumber, &c.cback)))
                    DDLogError(@"AUGraphSetNodeInputCallback failed");
            }
        }
        free(connections);
    }

    else { // First time
        [self configureAudioGraph:decoderMetadata];
    }

    DDLogVerbose(@"Initializing audio graph");
    if((err = AUGraphInitialize(_outputGraph))) {
        DDLogError(@"AUGraphInitialize failed: %d", err);
    }

    /*AudioStreamBasicDescription outFormat;
    UInt32 size = sizeof(outFormat);
    err = AudioUnitGetProperty(_outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFormat, &size); //Ensures we have correct format, just in case it didnt set properly
    DDLogVerbose(@"output unit input sample rate: %f", outFormat.mSampleRate);

    Float64 outSampleRate = 0.0;
    size = sizeof(Float64);
    AudioUnitGetProperty (_outputUnit,
                          kAudioUnitProperty_SampleRate,
                          kAudioUnitScope_Output,
                          0,
                          &outSampleRate,
                          &size);
    DDLogVerbose(@"output unit output sample rate %f", outSampleRate);*/
}

- (void)createAudioGraph
{
    int err;

    // Create Graph
    err = NewAUGraph(&_outputGraph);
    if(err) {
        DDLogError(@"NewAUGraph failed");
    }

    // Node descriptions
    AudioComponentDescription mixerDesc;
    mixerDesc.componentType = kAudioUnitType_Mixer;
    mixerDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    mixerDesc.componentFlags = 0;
    mixerDesc.componentFlagsMask = 0;
    mixerDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponentDescription outputDesc;
    outputDesc.componentType = kAudioUnitType_Output;
    outputDesc.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    outputDesc.componentFlags = 0;
    outputDesc.componentFlagsMask = 0;

    // Add nodes
    err = AUGraphAddNode(_outputGraph, &outputDesc, &_outputNode);
    if(err) {
        DDLogError(@"AUGraphAddNode failed (output)");
    }


    err = AUGraphAddNode(_outputGraph, &mixerDesc, &_mixerNode);
    if(err) {
        DDLogError(@"AUGraphAddNode failed (mixer)");
    }

    // Connect nodes together
    err = AUGraphConnectNodeInput(_outputGraph, _mixerNode, 0, _outputNode, 0);
    if(err) {
        DDLogError(@"AUGraphConnectNodeInput failed (mixer->output)");
    }

    // Open and fetch the units
    err = AUGraphOpen(_outputGraph);
    if(err) {
        DDLogError(@"AUGraphOpen failed");
    }

    err = AUGraphNodeInfo(_outputGraph, _outputNode, NULL, &_outputUnit);
    if(err) {
        DDLogError(@"AUGraphNodeInfo failed (output)");
    }

    err = AUGraphNodeInfo(_outputGraph, _mixerNode, NULL, &_mixerUnit);
    if(err) {
        DDLogError(@"AUGraphNodeInfo failed (mixer)");
    }

    // Setup mixer
    UInt32 numbuses = 1;
    err = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &numbuses, sizeof(numbuses));
    if(err) {
        DDLogError(@"AudioUnitSetProperty(kAudioUnitProperty_ElementCount:mixerUnit input) failed");
    }

    err = AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Input, 0, 1.0, 0);
    if(err) {
        DDLogError(@"AudioUnitSetProperty(kMultiChannelMixerParam_Volume:mixerUnit input) failed");
    }
    err = AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, _volume, 0);
    if(err) {
        DDLogError(@"AudioUnitSetProperty(kMultiChannelMixerParam_Volume:mixerUnit output) failed");
    }


    // Set input callbacks to mixer
    AURenderCallbackStruct renderCallback;
    memset(&renderCallback, 0, sizeof(AURenderCallbackStruct));
    renderCallback.inputProc = renderProc;
    renderCallback.inputProcRefCon = (__bridge void *)self;

    int auBufferSize = 4096*2;
    void *auBufferContents = malloc(auBufferSize);
    auBuffer = [NSData dataWithBytesNoCopy:auBufferContents length:auBufferSize freeWhenDone:YES];

    err = AUGraphSetNodeInputCallback(_outputGraph, _mixerNode, 0, &renderCallback);
}

- (void)configureAudioGraph:(DecoderMetadata)decoderMetadata
{
    // Setup audio format chain
    int err;
    AudioStreamBasicDescription outFormat;
    UInt32 size = sizeof(outFormat);

    err = AudioUnitGetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFormat, &size);
    if(err) {
        DDLogError(@"AudioUnitGetProperty(kAudioUnitProperty_StreamFormat:mixerUnit input) failed");
    }

    outFormat.mSampleRate = decoderMetadata.sampleRate;

    err = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFormat, sizeof(AudioStreamBasicDescription));
    if(err) {
        DDLogError(@"AudioUnitSetProperty(kAudioUnitProperty_StreamFormat:mixerUnit input) failed");
    }

    size = sizeof(outFormat);
    err = AudioUnitGetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFormat, &size); //Ensures we have correct format, just in case it didnt set properly
    if(err) {
        DDLogError(@"AudioUnitGetProperty(kAudioUnitProperty_StreamFormat:mixerUnit input) failed");
    }

    err = AudioUnitSetProperty(_mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &outFormat, &size);
    if(err) {
        DDLogError(@"AudioUnitSetProperty(kAudioUnitProperty_StreamFormat:mixerUnit output) failed");
    }

    // Set up converter
    _inFormat.mSampleRate = decoderMetadata.sampleRate;
    _inFormat.mChannelsPerFrame = decoderMetadata.numberOfChannels;
    _inFormat.mFormatID = kAudioFormatLinearPCM;
    _inFormat.mFormatFlags = kLinearPCMFormatFlagIsPacked;
    _inFormat.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
    int bps = decoderMetadata.bitsPerSample;
    _inFormat.mBitsPerChannel = bps;
    _inFormat.mBytesPerPacket = bps/8*_inFormat.mChannelsPerFrame;
    _inFormat.mFramesPerPacket = 1;
    _inFormat.mBytesPerFrame = bps/8*_inFormat.mChannelsPerFrame;

    if(converter) {
        err = AudioConverterDispose(converter);
        if(err) {
            DDLogError(@"AudioConverterDispose failed");
        }
    }

    err = AudioConverterNew(&_inFormat, &outFormat, &converter);
    if(err) {
        DDLogError(@"AudioConverterNew failed");
    }
    
    // Create FIFOBuffer with FIFOBUFFER_TOTAL_SECONDS of space
    fifoBuffer = [[FIFOBuffer alloc] initWithSize:_inFormat.mBytesPerFrame*_inFormat.mSampleRate*FIFOBUFFER_TOTAL_SECONDS];
}

- (id<DecoderProtocol>)decoderForFile:(NSString *)filename
{
    NSString *ext = [[filename pathExtension] lowercaseString];

    PluginManager *pluginManager = [PluginManager sharedInstance];
    Class decoderClass = [pluginManager decoderClassForExtension:ext];

    return [((id<DecoderProtocol>)[decoderClass alloc]) initWithMusicController:self andExtension:ext];
}

- (void)pause
{
    if([self status] == MusicControllerPlaying) {
        [self setStatus:MusicControllerPaused];
        AUGraphStop(_outputGraph);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"pausedPlayback" object:_currentTrack];
    }
}

- (void)unpause
{
    if([self status] == MusicControllerPaused) {
        [self setStatus:MusicControllerPlaying];
        AUGraphStart(_outputGraph);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"unpausedPlayback" object:_currentTrack];
    }
}

- (void)receivedPlayTrackNotification:(NSNotification *)notification
{
    if([self decoderStatus] != MusicControllerDecoderIdle) { //still playing something at the moment
        AUGraphStop(_outputGraph);
        [self setStatus:MusicControllerStopped];
        
        // This ensures the decoding queue is empty. Otherwise an already scheduled decoding task
        // could run at the same time as this function and mess up stuff
        dispatch_sync(decoding_queue, ^() {});
    }
    _currentTrack = [notification object];
    NSString *fp = [_currentTrack filename];
    DDLogVerbose(@"Attempting to play %@", fp);

    fileHandle = [NSFileHandle fileHandleForReadingAtPath:fp];
    if(fileHandle == nil) {
        DDLogError(@"File does not exist at %@", fp);
        PlaylistTrack *t = _currentTrack;
        _currentTrack = nil;
        [t setHasErrorOpeningFile:YES];
        [[t playlist] playNextTrackAfter:t];
        return;
    }

    [self setDecoderStatus:MusicControllerDecodingSong];
    [self setStatus:MusicControllerPlaying];

    currentDecoder = [self decoderForFile:fp];
    DecoderMetadata metadata = [currentDecoder decodeMetadata];
    _totalFrames = metadata.totalSamples;
    DDLogVerbose(@"total frames: %llu", metadata.totalSamples);
    DDLogVerbose(@"bitrate: %d", metadata.bitsPerSample);

    [_currentTrack setHasErrorOpeningFile:NO]; // Clear any prev error as it's ok now
    
    NSDate *d = [NSDate date];
    [self createOrReconfigureAudioGraph:metadata];
    DDLogVerbose(@"time to setup audio graph: %f", [[NSDate date] timeIntervalSinceDate:d]);

    _prevElapsedTimeSent = 0;
    [self setElapsedFrames:0];
    [fifoBuffer reset];
    dispatch_sync(decoding_queue, ^() {
        NSDate *timeBeforeFilling = [NSDate date];
        [self fillBuffer]; // run in decoding queue just in case
        double t = [[NSDate date] timeIntervalSinceDate:timeBeforeFilling];
        DDLogVerbose(@"Time to fill %d sec of audio buffer: %f seconds", FIFOBUFFER_STOP_REFILL_SECONDS, t);
    });

    AUGraphStart(_outputGraph);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"startedPlayback" object:_currentTrack];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"pluginNewTrackPlaying" object:[_currentTrack attributes]];
    //CAShow(_outputGraph);

};

- (void)receivedSeekTrackNotification:(NSNotification *)notification
{
    if([self status] == MusicControllerStopped) return;

    long sampleno = _elapsedFrames;
    if([[notification name] isEqual: @"seekTrack"]) {
        float seekto = [(NSNumber *)[notification object] floatValue];
        sampleno = seekto * _totalFrames;
        DDLogVerbose(@"Seeking to %f percent", seekto);
    }
    else if([[notification name] isEqual: @"seekTrackByJump"]) {
        NSInteger direction = [(NSNumber *)[notification object] integerValue];
        sampleno += direction * (int)_inFormat.mSampleRate * 5; // 5 seconds
        if(sampleno < 0) sampleno = 0;
        DDLogVerbose(@"Seeking by %ld seconds [new position = %f s]", direction*5, (float)sampleno/(float)_inFormat.mSampleRate);
    }
    else {
        DDLogError(@"Unsupported seek notification received");
        return;
    }

    AUGraphStop(_outputGraph);
    [self setDecoderStatus:MusicControllerSeekingSong];
    dispatch_sync(decoding_queue, ^() {}); //Flush decoding queue
    [currentDecoder seekToFrame:sampleno];
    [fifoBuffer reset];
    [self setDecoderStatus:MusicControllerDecodingSong];
    dispatch_sync(decoding_queue, ^() {
        [self fillBuffer]; // run in decoding queue just in case
    });
    [self setElapsedFrames:sampleno];

    if([self status] == MusicControllerPlaying)
        AUGraphStart(_outputGraph);
}

-(void)fillBuffer {
    // Fill until it is over FIFOBUFFER_STOP_REFILL_SECONDS of buffer
    size_t size = [fifoBuffer stored];
    while(size < _inFormat.mBytesPerFrame*_inFormat.mSampleRate*FIFOBUFFER_STOP_REFILL_SECONDS && [self decoderStatus] == MusicControllerDecodingSong) {
        DecodeStatus status = [currentDecoder decodeNextFrame];
        if(status == DecoderEOF) {
            [self setDecoderStatus:MusicControllerDecodedSong];
        }
        size = [fifoBuffer stored];
        
        /* Induces a purposeful buffer underflow
        static BOOL hiccup = false;
        if(_elapsedFrames > 500000 && hiccup == false) {
            sleep(1);
            hiccup = true;
        }*/
    }
}

- (NSData *)readInput:(unsigned long long)bytes {
    return [fileHandle readDataOfLength:(NSUInteger)bytes];
}

- (void)seekInput:(unsigned long long)offset {
    [fileHandle seekToFileOffset:offset];
}

- (void)seekInputToEnd {
    [fileHandle seekToEndOfFile];
}

- (unsigned long long)inputPosition {
    return [fileHandle offsetInFile];
}

- (unsigned long long)inputLength {
    unsigned long long curpos = [self inputPosition];
    [self seekInputToEnd];
    unsigned long long length = [self inputPosition];
    [self seekInput:curpos];
    return length;
}

- (void)trackEndedNaturally {
    PlaylistTrack *t = _currentTrack;
    [self stop];
    [[t playlist] playNextTrackAfter:t];
}

- (PlaylistTrack*)getCurrentTrack { // all instance variables are private
    return _currentTrack;
}

- (void)stop {
    AUGraphStop(_outputGraph);
    
    [self setStatus:MusicControllerStopped];
    [self setDecoderStatus:MusicControllerDecoderIdle];
    _currentTrack = nil;
    _totalFrames = 0;
    [self setElapsedFrames:0];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"stoppedPlayback" object:nil];
    [fifoBuffer reset];
}

- (void)setElapsedFrames:(unsigned long long)elapsedFrames {
    _elapsedFrames = elapsedFrames;

    float sec = [self elapsedSeconds];
    if(fabs(sec - _prevElapsedTimeSent) > 0.1) {
        _prevElapsedTimeSent = sec;

        NSNumber *timeElapsed = [NSNumber numberWithFloat:sec];
        NSNumber *timeTotal = [NSNumber numberWithFloat:(float)_totalFrames / (float) _inFormat.mSampleRate];

        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setObject:timeElapsed forKey:@"timeElapsed"];
        [dict setObject:timeTotal forKey:@"timeTotal"];
        
        
        void (^postNotificationBlock)(void) = ^() {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"playbackProgress" object:dict];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"pluginPlaybackProgress" object:dict];
        };
        
        if(dispatch_get_current_queue() == dispatch_get_main_queue()) {
            postNotificationBlock();
        }
        else { // Only post notfications from a main thread as there are UI updates
            dispatch_async(dispatch_get_main_queue(), postNotificationBlock);
        }
    }
}

- (float)elapsedSeconds
{
    float sec = (float)_elapsedFrames / (float)_inFormat.mSampleRate;
    return sec;
}

- (float)volume {
    return _volume;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    [[NSUserDefaults standardUserDefaults] setFloat:_volume forKey:@"volume"];
    
    if(_mixerUnit) {
        int err = AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Volume, kAudioUnitScope_Output, 0, volume, 0);
        if(err) {
            DDLogError(@"AudioUnitSetProperty(kMultiChannelMixerParam_Volume:mixerUnit output) failed");
        }
    }
}

-(MusicControllerStatus)status {
    return _status;
}

-(void)setStatus:(MusicControllerStatus)status
{
    _status = status;
    if(_currentTrack) {
        [_currentTrack setPlaybackStatus:status];
        DDLogVerbose(@"hi for %@", [_currentTrack filename]);
    }
}

@end
