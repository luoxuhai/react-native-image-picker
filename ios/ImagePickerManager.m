#import "ImagePickerManager.h"
#import "ImagePickerUtils.h"
#import <React/RCTConvert.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

@import MobileCoreServices;

@interface ImagePickerManager ()

@property (nonatomic, strong) RCTResponseSenderBlock callback;
@property (nonatomic, copy) NSDictionary *options;

@end

@interface ImagePickerManager (UIImagePickerControllerDelegate) <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@interface ImagePickerManager (UIAdaptivePresentationControllerDelegate) <UIAdaptivePresentationControllerDelegate>
@end

#if __has_include(<PhotosUI/PHPicker.h>)
@interface ImagePickerManager (PHPickerViewControllerDelegate) <PHPickerViewControllerDelegate>
@end
#endif

@implementation ImagePickerManager

NSString *errCameraUnavailable = @"camera_unavailable";
NSString *errPermission = @"permission";
NSString *errOthers = @"others";
static NSString *DID_FINISH_PICKING = @"didFinishPicking";

RNImagePickerTarget target;

BOOL photoSelected = NO;

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(launchCamera:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    target = camera;
    photoSelected = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self launchImagePicker:options callback:callback];
    });
}

RCT_EXPORT_METHOD(launchImageLibrary:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    target = library;
    photoSelected = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self launchImagePicker:options callback:callback];
    });
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[DID_FINISH_PICKING];
}

- (NSDictionary *)constantsToExport
{
 return @{ @"DID_FINISH_PICKING": DID_FINISH_PICKING };
}

- (void)launchImagePicker:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback
{
    self.callback = callback;
    
    if (target == camera && [ImagePickerUtils isSimulator]) {
        self.callback(@[@{@"errorCode": errCameraUnavailable}]);
        return;
    }
    
    self.options = options;

    if (target == library) {
        PHPickerConfiguration *configuration = [ImagePickerUtils makeConfigurationFromOptions:options target:target];
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        picker.modalPresentationStyle = [RCTConvert UIModalPresentationStyle:options[@"presentationStyle"]];
        picker.presentationController.delegate = self;
            
        [self checkPhotosPermissions:^(BOOL granted) {
            if (!granted) {
                self.callback(@[@{@"errorCode": errPermission}]);
                return;
            }
            [self showPickerViewController:picker];
        }];
        
        return;
    } else {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        [ImagePickerUtils setupPickerFromOptions:picker options:self.options];
        picker.delegate = self;
        [self showPickerViewController:picker];
    }
}

- (void) showPickerViewController:(UIViewController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = RCTPresentedViewController();
        [root presentViewController:picker animated:YES completion:nil];
    });
}

#pragma mark - Helpers

CGImagePropertyOrientation CGImagePropertyOrientationForUIImageOrientation(UIImageOrientation uiOrientation) {
    //code from here: https://developer.apple.com/documentation/imageio/cgimagepropertyorientation?language=objc
    switch (uiOrientation) {
        case UIImageOrientationUp: return kCGImagePropertyOrientationUp;
        case UIImageOrientationDown: return kCGImagePropertyOrientationDown;
        case UIImageOrientationLeft: return kCGImagePropertyOrientationLeft;
        case UIImageOrientationRight: return kCGImagePropertyOrientationRight;
        case UIImageOrientationUpMirrored: return kCGImagePropertyOrientationUpMirrored;
        case UIImageOrientationDownMirrored: return kCGImagePropertyOrientationDownMirrored;
        case UIImageOrientationLeftMirrored: return kCGImagePropertyOrientationLeftMirrored;
        case UIImageOrientationRightMirrored: return kCGImagePropertyOrientationRightMirrored;
    }
}

NSData* extractImageData(UIImage* image){
    CFMutableDataRef imageData = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(imageData, kUTTypeJPEG, 1, NULL);
    
    CFStringRef orientationKey[1];
    CFTypeRef   orientationValue[1];
    CGImagePropertyOrientation CGOrientation = CGImagePropertyOrientationForUIImageOrientation(image.imageOrientation);

    orientationKey[0] = kCGImagePropertyOrientation;
    orientationValue[0] = CFNumberCreate(NULL, kCFNumberIntType, &CGOrientation);

    CFDictionaryRef imageProps = CFDictionaryCreate( NULL, (const void **)orientationKey, (const void **)orientationValue, 1,
                    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    CGImageDestinationAddImage(destination, image.CGImage, imageProps);
    
    CGImageDestinationFinalize(destination);
    
    CFRelease(destination);
    CFRelease(orientationValue[0]);
    CFRelease(imageProps);
    return (__bridge NSData *)imageData;
}

-(NSMutableDictionary *)mapImageToAsset:(NSData *)imageData phAsset:(PHAsset *)phAsset {
    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    NSString *filename = [phAsset valueForKey:@"filename"];
    NSString *outputURL = [[self getTmpDirectory] stringByAppendingPathComponent:filename];

    [imageData writeToFile:outputURL atomically:YES];

    NSURL *fileURL = [NSURL fileURLWithPath:outputURL];
    
    asset[@"uri"] = [fileURL absoluteString];
    asset[@"type"] = [ImagePickerUtils getFileTypeFromUrl:fileURL];
    asset[@"fileSize"] = [ImagePickerUtils getFileSizeFromUrl:fileURL];
    asset[@"fileName"] = filename;
    asset[@"width"] = @(phAsset.pixelHeight);
    asset[@"height"] = @(phAsset.pixelHeight);
    asset[@"id"] = phAsset.localIdentifier;
    CLLocation * location = phAsset.location;
    asset[@"location"] = @{@"speed": @(location.speed),
                            @"altitude": @(location.altitude),
                            @"latitude": @(location.coordinate.latitude),
                            @"longitude": @(location.coordinate.longitude)};
    
    return asset;
}

-(NSMutableDictionary *)mapVideoToAsset:(AVAsset*)avAsset phAsset:(PHAsset * _Nullable)phAsset error:(NSError **)error {
    NSURL *sourceURL = [(AVURLAsset *)avAsset URL];
    NSString *filename = [phAsset valueForKey:@"filename"];
    NSString *outputURL = [[self getTmpDirectory] stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:outputURL];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Delete file if it already exists
    if ([fileManager fileExistsAtPath:fileURL.path]) {
        [fileManager removeItemAtURL:fileURL error:nil];
    }
    [fileManager copyItemAtURL:sourceURL toURL:fileURL error:error];

    if (error && *error) {
        return nil;
    }

    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    CGSize dimentions = [ImagePickerUtils getVideoDimensionsFromUrl:fileURL];
    asset[@"fileName"] = filename;
    asset[@"duration"] = @(phAsset.duration * 1000);
    asset[@"uri"] = [fileURL absoluteString];
    asset[@"type"] = [ImagePickerUtils getFileTypeFromUrl:fileURL];
    asset[@"fileSize"] = [ImagePickerUtils getFileSizeFromUrl:fileURL];
    asset[@"width"] = @(dimentions.width);
    asset[@"height"] = @(dimentions.height);
    asset[@"id"] = phAsset.localIdentifier;
    CLLocation * location = phAsset.location;
    asset[@"location"] = @{@"speed": @(location.speed),
                           @"altitude": @(location.altitude),
                           @"latitude": @(location.coordinate.latitude),
                           @"longitude": @(location.coordinate.longitude)};

    return asset;
}

-(NSMutableDictionary *)mapCameraImageToAsset:(UIImage *)image {
    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"jpg"];
    NSString *outputURL = [[self getTmpDirectory] stringByAppendingPathComponent:fileName];
    NSURL *fileURL = [NSURL fileURLWithPath:outputURL];

    NSData *data = extractImageData(image);
    [data writeToFile:outputURL atomically:YES];

    asset[@"fileName"] = fileName;
    asset[@"uri"] = fileURL.absoluteString;
    asset[@"type"] = @"image/jpeg";
    asset[@"fileSize"] = [ImagePickerUtils getFileSizeFromUrl:fileURL];
    asset[@"width"] = @(CGImageGetWidth(image.CGImage));
    asset[@"height"] = @(CGImageGetHeight(image.CGImage));

    return asset;
}

-(NSMutableDictionary *)mapCameraVideoToAsset:(NSURL *)url {
    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    NSString *fileName = [url lastPathComponent];
    NSString *outputURL = [[self getTmpDirectory] stringByAppendingPathComponent:fileName];
    NSURL *fileURL = [NSURL fileURLWithPath:outputURL];

    [[NSFileManager defaultManager] moveItemAtURL:url toURL:fileURL error:nil];

    CGSize dimentions = [ImagePickerUtils getVideoDimensionsFromUrl:fileURL];
    asset[@"fileName"] = fileName;
    asset[@"uri"] = fileURL.absoluteString;
    asset[@"type"] = [ImagePickerUtils getFileTypeFromUrl:fileURL];
    asset[@"fileSize"] = [ImagePickerUtils getFileSizeFromUrl:fileURL];
    asset[@"width"] = @(dimentions.width);
    asset[@"height"] = @(dimentions.height);
    AVAsset * avasset = [AVAsset assetWithURL:fileURL];
    asset[@"duration"] = @(CMTimeGetSeconds(avasset.duration) * 1000);

    return asset;
}

- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    }
    else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    }
    else {
        callback(NO);
    }
}

- (void)checkPhotosPermissions:(void(^)(BOOL granted))callback
{
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                callback(YES);
                return;
            }
            else {
                callback(NO);
                return;
            }
        }];
    }
    else {
        callback(NO);
    }
}

// Both camera and photo write permission is required to take picture/video and store it to public photos
- (void)checkCameraAndPhotoPermission:(void(^)(BOOL granted))callback
{
    [self checkCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            callback(NO);
            return;
        }

        [self checkPhotosPermissions:^(BOOL photoGranted) {
            if (!photoGranted) {
                callback(NO);
                return;
            }
            callback(YES);
        }];
    }];
}

- (void)checkPermission:(void(^)(BOOL granted)) callback
{
    void (^permissionBlock)(BOOL) = ^(BOOL permissionGranted) {
        if (!permissionGranted) {
            callback(NO);
            return;
        }
        callback(YES);
    };

    if (target == camera && [self.options[@"saveToPhotos"] boolValue]) {
        [self checkCameraAndPhotoPermission:permissionBlock];
    }
    else if (target == camera) {
        [self checkCameraPermissions:permissionBlock];
    }
    else {
        if (@available(iOS 11.0, *)) {
            callback(YES);
        }
        else {
            [self checkPhotosPermissions:permissionBlock];
        }
    }
}

- (NSString*) getTmpDirectory {
    NSString *TMP_DIRECTORY = @"react-native-photos-picker/";
    NSString *tmpFullPath = [NSTemporaryDirectory() stringByAppendingString:TMP_DIRECTORY];
    
    BOOL isDir;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:tmpFullPath isDirectory:&isDir];
    if (!exists) {
        [[NSFileManager defaultManager] createDirectoryAtPath: tmpFullPath
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return tmpFullPath;
}

@end

@implementation ImagePickerManager (UIImagePickerControllerDelegate)

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    dispatch_block_t dismissCompletionBlock = ^{
        NSMutableArray<NSDictionary *> *assets = [[NSMutableArray alloc] initWithCapacity:1];

        if (photoSelected == YES) {
           return;
        }
        photoSelected = YES;
        
        if ([info[UIImagePickerControllerMediaType] isEqualToString:(NSString *) kUTTypeImage]) {
            NSDictionary *asset = [self mapCameraImageToAsset:[ImagePickerUtils getUIImageFromInfo:info]];
            [assets addObject:asset];
        } else {
            NSDictionary *asset = [self mapCameraVideoToAsset:info[UIImagePickerControllerMediaURL]];
            [assets addObject:asset];
        }

        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
        response[@"assets"] = assets;
        self.callback(@[response]);
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:dismissCompletionBlock];
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:^{
            self.callback(@[@{@"didCancel": @YES}]);
        }];
    });
}

@end

@implementation ImagePickerManager (presentationControllerDidDismiss)

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
    self.callback(@[@{@"didCancel": @YES}]);
}

@end

@implementation ImagePickerManager (PHPickerViewControllerDelegate)

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14))
{
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (photoSelected == YES) {
        return;
    }
    photoSelected = YES;
    
    if (results.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.callback(@[@{@"didCancel": @YES}]);
        });
        return;
    }
    
    [self sendEventWithName:DID_FINISH_PICKING body:@"didFinishPicking"];
    
    dispatch_group_t completionGroup = dispatch_group_create();
    NSMutableArray<NSDictionary *> *assets = [[NSMutableArray alloc] initWithCapacity:results.count];
    
    for (PHPickerResult *result in results) {
        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
        fetchOptions.includeHiddenAssets = YES;
        fetchOptions.fetchLimit = 1;
 
        PHFetchResult* fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[result.assetIdentifier] options:fetchOptions];
        
        PHAsset *asset = fetchResult.firstObject;
        
        if (asset == nil) {
            continue;
        }
                        
        dispatch_group_enter(completionGroup);

        if(asset.mediaType == PHAssetMediaTypeImage) {
            PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
            options.synchronous = NO;
            options.networkAccessAllowed = YES;
            options.version = PHImageRequestOptionsVersionCurrent;
            options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

            [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset options:options 
                resultHandler:^(NSData *_Nullable imageData, NSString *_Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary *_Nullable info) {
                
                   NSMutableDictionary *imageAsset = [self mapImageToAsset:imageData phAsset:asset];
                   [assets addObject:imageAsset];
                   dispatch_group_leave(completionGroup);
             }];
        } else if(asset.mediaType == PHAssetMediaTypeVideo) {
            PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
            options.version = PHVideoRequestOptionsVersionCurrent;
            options.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat;
            options.networkAccessAllowed = YES;

            [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options
                resultHandler:^(AVAsset * avAsset, AVAudioMix * audioMix,
                     NSDictionary *info) {
                        [assets addObject:[self mapVideoToAsset:avAsset phAsset:asset error:nil]];
                        dispatch_group_leave(completionGroup);
                     }];
        } else {
             dispatch_group_leave(completionGroup);
         }
    }

    dispatch_group_notify(completionGroup, dispatch_get_main_queue(), ^{
        if (assets.count != results.count) {
            self.callback(@[@{@"errorCode": errPermission}]);
            return;
        }
        
        //  mapVideoToAsset can fail and return nil.
        for (NSDictionary *asset in assets) {
            if (nil == asset) {
                self.callback(@[@{@"errorCode": errOthers}]);
                return;
            }
        }

        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
        [response setObject:assets forKey:@"assets"];

        self.callback(@[response]);
    });
}

@end
