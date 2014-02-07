//
//  GravatarController.m
//  Gitifier
//
//  Created by Thomas Loreit on 06.02.14.
//
//

#import "GravatarController.h"
#import "Utils.h"
#import "NSImage+RoundedCorners.h"

@interface GravatarController ()

@property (strong)  NSMutableDictionary *cachedImageDataForEmailAddress;
@property (strong)  NSMutableDictionary *requestForEmailAddress;
@property (assign)  int gravatarImageScale;
@property (assign)  int gravatarCornerRadius;

@end

@implementation GravatarController

+(GravatarController *)sharedController{
  static dispatch_once_t onceToken;
  
  static GravatarController *instance = nil;
 
  dispatch_once(&onceToken, ^{
    instance = [[GravatarController alloc] init];
  });
  
  return instance;
}


-(id)init{
  if((self = [super init])){
    self.cachedImageDataForEmailAddress = [NSMutableDictionary dictionary];
    self.requestForEmailAddress         = [NSMutableDictionary dictionary];
    self.gravatarImageScale = 150;
    self.gravatarCornerRadius = 10;
    
    //check if any retina display is attached
    if ([[NSScreen mainScreen] respondsToSelector:@selector(backingScaleFactor)]) {
      
      float bestScreenScaleFactor = 1.0f;
      
      for (NSScreen *screen in [NSScreen screens]) {
        float s = [screen backingScaleFactor];
        if (s > bestScreenScaleFactor)
          bestScreenScaleFactor = s;
      }
      
      self.gravatarImageScale *= bestScreenScaleFactor;
      self.gravatarCornerRadius *= bestScreenScaleFactor;
    }
  }
  return self;
}

-(NSData*)imageDataForEmailAddress:(NSString*)emailAddress completionHandler:(void (^)(NSString *emailAddress, NSData* data, NSError* connectionError)) handler{
  NSData *imageData = nil;
  
  @synchronized(self.cachedImageDataForEmailAddress){
    imageData = self.cachedImageDataForEmailAddress[emailAddress];
  
    if(!imageData || imageData.length==0){
      //request the image from gravatar
      @synchronized (self.requestForEmailAddress){
        BOOL isAlreadyRequested = [self.requestForEmailAddress[emailAddress] boolValue];

        if(!isAlreadyRequested){
          self.requestForEmailAddress[emailAddress] = @YES;
          
          NSString *gravatarImageLocation = [NSString stringWithFormat:@"http://www.gravatar.com/avatar/%@?s=%d", [[emailAddress MD5Hash] lowercaseString], self.gravatarImageScale];
          NSLog(@"fetching gravatar for %@ <%@>", emailAddress, gravatarImageLocation);
          
          [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:gravatarImageLocation]
                                                                    cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5]
                                             queue:[NSOperationQueue mainQueue]
                                 completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
          {
            NSImage *image=[[NSImage alloc] initWithData: data];
            data = image ? [[image imageWithCornerRadius: self.gravatarCornerRadius] TIFFRepresentation] : nil;
            
            @synchronized(self.cachedImageDataForEmailAddress){
              if(data && data.length>0)
                self.cachedImageDataForEmailAddress[emailAddress] = data;
            
              @synchronized(self.requestForEmailAddress){
                self.requestForEmailAddress[emailAddress] = @NO;
              }
            }
            
            if(handler)
              handler(emailAddress, data, connectionError);
          }];
        }
      }
    }
  }
  
  return imageData;
}

@end
