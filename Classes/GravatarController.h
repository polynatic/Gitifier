//
//  GravatarController.h
//  Gitifier
//
//  Created by Thomas Loreit on 06.02.14.
//
//

#import <Foundation/Foundation.h>

@interface GravatarController : NSObject

+(GravatarController*)sharedController;
-(NSData*)imageDataForEmailAddress:(NSString*)emailAddress completionHandler:(void (^)(NSString *emailAddress, NSData* imageData, NSError* connectionError))handler;

@end
