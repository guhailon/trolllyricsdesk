// Private-framework declaration header, from TrollSpeed (MIT, Copyright (c) 2023 Lessica).
// Copied unchanged except for this attribution comment. See README.md.

#ifndef LSApplicationProxy_h
#define LSApplicationProxy_h

#import <Foundation/Foundation.h>

@class LSPlugInKitProxy;

@interface LSApplicationProxy : NSObject
+ (LSApplicationProxy *)applicationProxyForIdentifier:(NSString *)bundleIdentifier;
- (BOOL)installed;
- (BOOL)restricted;
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSString *)shortVersionString;
- (NSString *)applicationType;
- (NSURL *)bundleURL;
- (NSURL *)dataContainerURL;
- (NSURL *)bundleContainerURL;
- (NSDictionary <NSString *, NSURL *> *)groupContainerURLs;
- (NSDictionary *)entitlements;
- (NSArray <LSPlugInKitProxy *> *)plugInKitPlugins;
@end

#endif /* LSApplicationProxy_h */
