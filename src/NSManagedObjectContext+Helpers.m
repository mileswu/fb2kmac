//
//  NSManagedObjectContext+Helpers.m
//  dokibox
//
//  Created by Miles Wu on 24/10/2013.
//  Copyright (c) 2015 Miles Wu and contributors. All rights reserved.
//

#import "NSManagedObjectContext+Helpers.h"

@implementation NSManagedObjectContext (Helpers)

-(BOOL)belongsToSameStoreAs:(NSManagedObjectContext *)context;
{
    return [context persistentStoreCoordinator] == [self persistentStoreCoordinator];
}

-(NSManagedObjectContext*)newContext
{
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:[self persistentStoreCoordinator]];
    return context;
}

@end
