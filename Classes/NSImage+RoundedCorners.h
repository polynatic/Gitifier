//
//  NSImage+RoundedCorners.h
//  Gitifier
//


#import <Cocoa/Cocoa.h>

@interface NSImage (RoundedCorners)

- (NSImage *)imageWithCornerRadius:(NSInteger)radius;
    
@end
