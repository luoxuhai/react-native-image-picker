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

-(NSMutableDictionary *)mapImageToAsset:(NSData *)imageData phAsset:(PHAsset *)phAsset {
    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    NSString *filename = target == camera ? [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"jpg"] : [phAsset valueForKey:@"filename"];

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
    NSString *filename = target == camera ? [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"mov"] : [phAsset valueForKey:@"filename"];
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
        PHAsset *asset = [ImagePickerUtils fetchPHAssetOnIOS13:info];

        if (photoSelected == YES) {
           return;
        }
        photoSelected = YES;

        if ([info[UIImagePickerControllerMediaType] isEqualToString:(NSString *) kUTTypeImage]) {
            NSData *data = [NSData dataWithContentsOfFile:[info[UIImagePickerControllerImageURL] absoluteString]];

            NSDictionary *imageAsset = [self mapImageToAsset:data phAsset:asset];
            [assets addObject:imageAsset];
        } else {
            AVAsset *avAsset = [AVAsset assetWithURL:info[UIImagePickerControllerMediaURL]];
            NSDictionary *videoAsset = [self mapVideoToAsset:avAsset phAsset:asset error:nil];
            [assets addObject:videoAsset];
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
        NSItemProvider *provider = result.itemProvider;
        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
        fetchOptions.includeHiddenAssets = YES;

        PHFetchResult* fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[result.assetIdentifier] options:fetchOptions];
        PHAsset *asset = fetchResult.firstObject;
        
        dispatch_group_enter(completionGroup);

        if(asset.mediaType == PHAssetMediaTypeImage) {
            PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
            options.synchronous = YES;
            options.networkAccessAllowed = YES;
            options.version = PHImageRequestOptionsVersionCurrent;
            options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
            options.resizeMode = PHImageRequestOptionsResizeModeNone;

            float maxWidth = [self.options[@"maxWidth"] floatValue];
            float maxHeight = [self.options[@"maxHeight"] floatValue];
            CGSize targetSize = CGSizeMake(maxWidth, maxHeight);

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
